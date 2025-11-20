"""Application configuration and logging helpers."""
from __future__ import annotations

import logging
from logging.handlers import RotatingFileHandler
from typing import List

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    api_key: str = "dev-api-key"
    database_url: str = "sqlite:///./data/jobs.db"
    log_level: str = "INFO"
    allowed_origins: List[str] = [
        "http://100.100.30.35:35000",
        "http://127.0.0.1:35000",
    ]
    threads_compat_mode: bool = True  # thread_id省略を許可する互換モード（Phase A/Bで使用）

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
    )

    @field_validator("allowed_origins", mode="before")
    @classmethod
    def split_origins(cls, value):
        if isinstance(value, str):
            return [origin.strip() for origin in value.split(",") if origin.strip()]
        return value


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
