# db_helpers.py
import config


class AppDatabaseError(Exception):
    """Исключение слоя работы с БД. Технический текст хранится только для отладки."""
    def __init__(self, user_message, technical_message=None):
        Exception.__init__(self, user_message)
        self.user_message = user_message
        self.technical_message = technical_message


NEUTRAL_ERROR = "Операция не выполнена. Обратитесь к администратору безопасности."


def _debug_print_error(e):
    if getattr(config, 'DEBUG_MODE', False):
        print("DB ERROR: {}".format(e))


def safe_rollback(conn):
    try:
        if conn:
            conn.rollback()
    except Exception:
        pass


def _handle_db_exception(conn, e):
    safe_rollback(conn)
    _debug_print_error(e)
    raise AppDatabaseError(NEUTRAL_ERROR, str(e))


def fetch_all(conn, sql, params=None):
    """Выполняет безопасный SELECT/вызов функции, возвращает список строк."""
    if params is None:
        params = ()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            rows = cur.fetchall()
        conn.commit()
        return rows
    except Exception as e:
        _handle_db_exception(conn, e)


def fetch_one(conn, sql, params=None):
    """Выполняет безопасный SELECT/вызов функции, возвращает одну строку."""
    if params is None:
        params = ()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            row = cur.fetchone()
        conn.commit()
        return row
    except Exception as e:
        _handle_db_exception(conn, e)


def execute_status_function(conn, sql, params=None):
    """
    Выполняет функцию БД, которая возвращает (success, message).
    Возвращает безопасное сообщение, сформированное на стороне БД.
    """
    row = fetch_one(conn, sql, params)
    if not row:
        return False, "Операция не выполнена."
    return bool(row[0]), row[1]
