#!/bin/bash
# Mails the status and recent journal of a failed systemd unit.
# Invoked by notify-failure@.service with the failed unit's name as $1.
#
# SMTP settings come from /etc/failure-mail.env (see failure-mail.env.example);
# the Discourse container's outbound SMTP account works well for this.

set -u

unit="$1"
host="$(hostname -f 2>/dev/null || hostname)"

# shellcheck disable=SC1091
. /etc/failure-mail.env

: "${SMTP_HOST:?}" "${SMTP_PORT:=25}" "${SMTP_USER:?}" "${SMTP_PASSWORD:?}" "${MAIL_FROM:?}" "${MAIL_TO:?}"

body="$(mktemp)"
trap 'rm -f "$body"' EXIT

{
    printf 'From: %s\r\n' "$MAIL_FROM"
    printf 'To: %s\r\n' "$MAIL_TO"
    printf 'Subject: [%s] systemd unit %s failed\r\n' "$host" "$unit"
    printf 'Date: %s\r\n' "$(date -R)"
    printf 'Content-Type: text/plain; charset=UTF-8\r\n'
    printf '\r\n'
    systemctl status --no-pager --lines=0 "$unit" 2>&1
    printf '\n---- journal (last 80 lines) ----\n'
    journalctl --no-pager -n 80 -u "$unit" 2>&1
} | sed 's/$/\r/' > "$body"

curl --silent --show-error \
    --url "smtp://${SMTP_HOST}:${SMTP_PORT}" \
    --ssl-reqd \
    --user "${SMTP_USER}:${SMTP_PASSWORD}" \
    --mail-from "$MAIL_FROM" \
    --mail-rcpt "$MAIL_TO" \
    --upload-file "$body"
