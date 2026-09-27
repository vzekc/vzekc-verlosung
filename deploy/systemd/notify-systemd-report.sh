#!/bin/bash
# Mails the report block of a unit's most recent run, if it printed one.
# Invoked by notify-report@.service with the unit's name as $1.
#
# The report is the text between "---- SYNC REPORT BEGIN ----" and
# "---- SYNC REPORT END ----" in the run's journal output. A run without
# changes or problems prints no block, and no mail is sent.
#
# SMTP settings come from /etc/failure-mail.env, shared with
# notify-systemd-failure.sh.

set -u

unit="$1"
host="$(hostname -f 2>/dev/null || hostname)"

# shellcheck disable=SC1091
. /etc/failure-mail.env

: "${SMTP_HOST:?}" "${SMTP_PORT:=25}" "${SMTP_USER:?}" "${SMTP_PASSWORD:?}" "${MAIL_FROM:?}" "${MAIL_TO:?}"

invocation="$(systemctl show --property=InvocationID --value "$unit")"
[ -n "$invocation" ] || exit 0

report="$(journalctl --no-pager -o cat "_SYSTEMD_INVOCATION_ID=$invocation" 2>&1 |
    sed -n '/^---- SYNC REPORT BEGIN ----$/,/^---- SYNC REPORT END ----$/{//!p;}')"
[ -n "$report" ] || exit 0

body="$(mktemp)"
trap 'rm -f "$body"' EXIT

{
    printf 'From: %s\r\n' "$MAIL_FROM"
    printf 'To: %s\r\n' "$MAIL_TO"
    printf 'Subject: [%s] %s report\r\n' "$host" "$unit"
    printf 'Date: %s\r\n' "$(date -R)"
    printf 'Content-Type: text/plain; charset=UTF-8\r\n'
    printf '\r\n'
    printf '%s\n' "$report"
    printf '\nFull log: journalctl -u %s _SYSTEMD_INVOCATION_ID=%s\n' "$unit" "$invocation"
} | sed 's/$/\r/' > "$body"

curl --silent --show-error \
    --url "smtp://${SMTP_HOST}:${SMTP_PORT}" \
    --ssl-reqd \
    --user "${SMTP_USER}:${SMTP_PASSWORD}" \
    --mail-from "$MAIL_FROM" \
    --mail-rcpt "$MAIL_TO" \
    --upload-file "$body"
