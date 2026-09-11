"""Independent test oracle: padded matrix, channel-major intermediate, divmod.

Does not import implementation indexing, rounding, saturation or packing helpers.
Only small synthetic cases use this deliberately different memory organization.
"""
def oracle(w,h,n,channels,pixels):
    border = n//2
    grid = [[0]*(w+2*border) for _ in range(h+2*border)]
    for row in range(h):
        grid[row+border][border:border+w] = list(pixels[row*w:(row+1)*w])
    planes = []
    for channel in channels:
        kernel = [channel.weights[i:i+n] for i in range(0,n*n,n)]
        plane = []
        for row in range(h):
            values = []
            for col in range(w):
                total = channel.bias+sum(sum(a*b for a,b in zip(grid[row+r][col:col+n],kernel[r])) for r in range(n))
                if channel.shift:
                    divisor = 2**channel.shift
                    quotient,remainder = divmod(total,divisor)
                    total = quotient+(2*remainder >= divisor)
                if total < -32768:
                    total = -32768
                elif total > 32767:
                    total = 32767
                if channel.relu and total < 0:
                    total = 0
                values.append(total)
            plane.append(values)
        planes.append(plane)
    packed = bytearray()
    for row in range(h):
        for col in range(w):
            for plane in planes:
                unsigned = plane[row][col] % 65536
                packed.append(unsigned % 256)
                packed.append(unsigned//256)
    return bytes(packed)
