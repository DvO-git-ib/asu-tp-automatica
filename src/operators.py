# operators.py
from db_helpers import fetch_all, execute_status_function


def get_current_params(conn):
    """Текущие параметры оператора через функцию БД."""
    return fetch_all(
        conn,
        "SELECT object_name, current_value, unit, location FROM asu_schema.f_get_current_params()"
    )


def get_active_alarms(conn, limit=20):
    """Активные аварии через функцию БД."""
    return fetch_all(
        conn,
        "SELECT alarm_id, description, action_date, object_name, severity_level FROM asu_schema.f_get_active_alarms(%s)",
        (limit,)
    )


def confirm_alarm(conn, alarm_id):
    """Подтверждение выбранной аварии через функцию БД."""
    return execute_status_function(
        conn,
        "SELECT success, message FROM asu_schema.f_confirm_alarm(%s)",
        (alarm_id,)
    )
