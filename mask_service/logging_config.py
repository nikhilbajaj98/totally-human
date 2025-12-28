import logging
import os


def setup_logging() -> logging.Logger:
    """Configure root logger once with level and formatter."""
    level_name = os.getenv("LOG_LEVEL", "INFO").upper()
    level = getattr(logging, level_name, logging.INFO)

    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)s %(name)s :: %(message)s",
    )

    logger = logging.getLogger("mask_service")
    logger.debug("Logging configured", extra={"level": level_name})
    return logger


# Module-level logger configured on import
logger = setup_logging()