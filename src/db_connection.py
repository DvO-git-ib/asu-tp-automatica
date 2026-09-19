# db_connection.py
from getpass import getpass
import psycopg2
from psycopg2 import OperationalError, DatabaseError
import config


def normalize_login(login):
    """Возвращает имя пользователя PostgreSQL с префиксом user_."""
    login = (login or "").strip()
    if login and not login.startswith('user_'):
        login = 'user_' + login
    return login


def get_connection(login, password):
    """
    Подключение к PostgreSQL выполняется от имени пользователя БД.
    Клиентское приложение не подключается под postgres и не получает
    прямой доступ к базовым таблицам.
    """
    db_login = normalize_login(login)

    try:
        conn = psycopg2.connect(
            host=config.DB_HOST,
            port=config.DB_PORT,
            dbname=config.DB_NAME,
            user=db_login,
            password=password,
            connect_timeout=config.CONNECT_TIMEOUT,
            sslmode=config.DB_SSLMODE
        )
        conn.autocommit = False
        return conn
    except OperationalError as e:
        print("Ошибка подключения: проверьте логин/пароль или доступность сервера.")
        if config.DEBUG_MODE:
            print("Детали: {}".format(e))
        return None
    except DatabaseError as e:
        print("Ошибка базы данных.")
        if config.DEBUG_MODE:
            print("Детали: {}".format(e))
        return None
    except Exception as e:
        print("Непредвиденная ошибка подключения.")
        if config.DEBUG_MODE:
            print("Детали: {}".format(e))
        return None


def close_connection(conn):
    if conn is None:
        return
    try:
        conn.close()
    except Exception:
        pass


if __name__ == "__main__":
    login = input("Логин: ")
    pwd = getpass("Пароль: ")
    conn = get_connection(login, pwd)
    if conn:
        print("Подключение успешно.")
        close_connection(conn)
    else:
        print("Не удалось подключиться.")
