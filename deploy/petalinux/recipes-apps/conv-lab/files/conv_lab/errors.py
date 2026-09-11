class AdmissionError(ValueError):
    """Rejected input; no context or hardware side effects may be published."""


class EnforcementUnavailable(AdmissionError):
    """The requested isolation cannot be enforced on this host/identity."""
