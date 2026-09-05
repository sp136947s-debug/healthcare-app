from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "NIDAN API"
    openai_api_key: str = ""
    openai_model: str = "gpt-5.6-luna"
    openai_embedding_model: str = "text-embedding-3-small"
    database_url: str = "postgresql+psycopg://nidan:nidan@db:5432/nidan"
    cors_origins: str = "*"
    google_places_api_key: str = ""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
