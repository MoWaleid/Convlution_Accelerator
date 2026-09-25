# Hybrid classification qualification

The B32_CFGLUT125 release was exercised on the ZedBoard through the complete
demonstration path: browser GUI, Linux runtime, FPGA Conv1 accelerator, and the
native Cortex-A9 classifier tail. The captured `ship_03.png` run completed with
PASS status and produced the following result:

| Item | Observed value |
|---|---:|
| Predicted class | Ship |
| Confidence | 98.8% |
| FPGA Conv1 time | 0.145 ms |
| PS classifier-tail time | 19.041 ms |
| Combined FPGA + PS compute time | 19.186 ms |
| Whole runtime call | 31.405 ms |
| Output channels displayed | 16 |

The GUI screenshot is preserved as `hybrid_ship_B32_PASS.png` with SHA-256
`a297b037640e647c6f9cf77d83d57bd594672c6139bf914fbaac1dc88ec468d7`.
The hardware result remained bit-exact against the software reference. The
classifier is the trained K=16 CIFAR-10 model whose full test-set accuracy is
70.08%; classification accuracy is therefore a model property and is not used
as evidence of arithmetic correctness in the FPGA.

The reported FPGA and PS values are component execution times. The whole-call
measurement additionally includes runtime validation, file handling, process
startup, and result recording.
