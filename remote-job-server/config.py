"""Application configuration and logging helpers."""
from __future__ import annotations

import logging
from logging.handlers import RotatingFileHandler

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    api_key: str = "dev-api-key"
    database_url: str = "sqlite:///./data/jobs.db"
    log_level: str = "INFO"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


settings = Settings()


def setup_logging() -> None:
    """Configure application-wide logging."""
    logger = logging.getLogger()
    if logger.handlers:
        return

    level = getattr(logging, settings.log_level.upper(), logging.INFO)
    logger.setLevel(level)

    formatter = logging.Formatter(
        "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    )

    file_handler = RotatingFileHandler(
        "logs/server.log", maxBytes=10 * 1024 * 1024, backupCount=5
    )
    file_handler.setFormatter(formatter)
    file_handler.setLevel(level)

    console = logging.StreamHandler()
    console.setFormatter(formatter)
    console.setLevel(level)

    logger.addHandler(file_handler)
    logger.addHandler(console)
