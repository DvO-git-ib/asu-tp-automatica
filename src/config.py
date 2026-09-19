# config.py
import os

APP_TITLE = "АСУ ТП «Автоматика»"
APP_SUBTITLE = "Подсистема администрирования и контроля"
APP_VERSION = "3.8"

# Параметры подключения задаются переменными окружения.
DB_HOST = os.getenv("ASUTP_DB_HOST", "localhost")
DB_PORT = int(os.getenv("ASUTP_DB_PORT", "5432"))
DB_NAME = os.getenv("ASUTP_DB_NAME", "testt")
CONNECT_TIMEOUT = int(os.getenv("ASUTP_CONNECT_TIMEOUT", "5"))

# Для удаленного PostgreSQL рекомендуется ASUTP_DB_SSLMODE=require или verify-full.
DB_SSLMODE = os.getenv("ASUTP_DB_SSLMODE", "disable")
DEBUG_MODE = os.getenv("ASUTP_DEBUG", "0").lower() in ("1", "true", "yes", "on")

# Лимит действует только в пределах текущего запуска окна авторизации.
MAX_LOGIN_ATTEMPTS = int(os.getenv("ASUTP_MAX_LOGIN_ATTEMPTS", "3"))

LOGIN_WINDOW_SIZE = "430x290"
MAIN_WINDOW_SIZE = "1180x760"
