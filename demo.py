def safe_div(a, b):
    """Return a / b, or 0 when b is zero."""
    return a / b if b != 0 else 0


def greet(name):
    return "Hello, " + name
