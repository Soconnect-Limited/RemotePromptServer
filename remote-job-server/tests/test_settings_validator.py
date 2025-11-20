from utils.settings_validator import validate_custom_flags, validate_settings, ValidationError


def test_reserved_flag_rejected():
    with assert_raises("Reserved flag"):
        validate_custom_flags(["-r", "high"], "codex")


def test_reasoning_effort_ok_high():
    data = {"codex": {"reasoning_effort": "high"}}
    sanitized = validate_settings(data)
    assert sanitized["codex"]["reasoning_effort"] == "high"


def test_reasoning_effort_ok_extra_high():
    data = {"codex": {"reasoning_effort": "extra-high"}}
    sanitized = validate_settings(data)
    assert sanitized["codex"]["reasoning_effort"] == "extra-high"


def test_reasoning_effort_invalid():
    data = {"codex": {"reasoning_effort": "ultra"}}
    with assert_raises("Invalid reasoning_effort"):
        validate_settings(data)


class assert_raises:
    def __init__(self, contains: str):
        self.contains = contains

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, _traceback):
        if exc_type is None:
            raise AssertionError("Expected exception was not raised")
        if not isinstance(exc_value, ValidationError):
            raise AssertionError(f"Unexpected exception type: {exc_type}")
        if self.contains not in str(exc_value):
            raise AssertionError(f"Exception message does not contain '{self.contains}': {exc_value}")
        return True
