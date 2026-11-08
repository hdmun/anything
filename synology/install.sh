#!/bin/sh
# ssh-notify 를 NAS 에 설치·다시 올리기·제거한다. PC 의 deploy.ps1 이 올린 뒤 부른다:
#
#   sudo sh ~/ssh-notify-upload/install.sh            설치·다시 올리기
#   sudo sh ~/ssh-notify-upload/install.sh --remove   제거
#
# 설치 위치 /volume1/@ssh-notify 는 글자 그대로 쓴다. rm -rf 의 경로를 변수로 조합하지 않는다.
set -u
umask 077

if [ "$(id -u)" != "0" ]; then
    echo "root 로 실행한다: sudo sh $0 ${1:-}"
    exit 1
fi

# sudo 안에서는 ~ 와 $HOME 이 root 홈일 수 있다. 업로드 폴더는 이 스크립트의 위치로 찾는다.
UPLOAD_DIR=$(cd "$(dirname "$0")" && pwd)

remove_upload_dir() {
    # 웹훅 URL 이 홈에 남지 않게 지운다. 이름이 ssh-notify-upload 인 폴더만 지운다.
    if [ "$(basename "$UPLOAD_DIR")" = "ssh-notify-upload" ]; then
        rm -rf "$UPLOAD_DIR"
    fi
}

stop_detector() {
    if [ -f /volume1/@ssh-notify/ssh-notify.py ]; then
        /usr/bin/python3 /volume1/@ssh-notify/ssh-notify.py --stop
    fi
}

case "${1:-}" in
--remove)
    if ! stop_detector; then
        echo "감지 장치를 멈추지 못해서 지우지 않았다."
        exit 1
    fi
    rm -rf /volume1/@ssh-notify
    remove_upload_dir
    echo "지웠다: /volume1/@ssh-notify"
    echo "DSM 작업 2개(ssh-notify 부팅, ssh-notify 매시간)는 화면에서 직접 지운다."
    exit 0
    ;;
"")
    ;;
*)
    echo "모르는 인수: $1 (쓸 수 있는 것: --remove)"
    exit 1
    ;;
esac

for f in ssh-notify.py ssh-notify.env; do
    if [ ! -f "$UPLOAD_DIR/$f" ]; then
        echo "올린 파일이 없다: $UPLOAD_DIR/$f"
        exit 1
    fi
done

# 1. 폴더를 만들고 파일을 바꿔 끼운다. state/·logs/ 안의 파일은 건드리지 않는다.
mkdir -p /volume1/@ssh-notify/state /volume1/@ssh-notify/logs || exit 1
cp "$UPLOAD_DIR/ssh-notify.py" /volume1/@ssh-notify/ssh-notify.py.new || exit 1
cp "$UPLOAD_DIR/ssh-notify.env" /volume1/@ssh-notify/ssh-notify.env.new || exit 1
chmod 755 /volume1/@ssh-notify/ssh-notify.py.new
chmod 600 /volume1/@ssh-notify/ssh-notify.env.new
mv -f /volume1/@ssh-notify/ssh-notify.py.new /volume1/@ssh-notify/ssh-notify.py || exit 1
mv -f /volume1/@ssh-notify/ssh-notify.env.new /volume1/@ssh-notify/ssh-notify.env || exit 1
chown root:root /volume1/@ssh-notify /volume1/@ssh-notify/state /volume1/@ssh-notify/logs \
    /volume1/@ssh-notify/ssh-notify.py /volume1/@ssh-notify/ssh-notify.env
chmod 755 /volume1/@ssh-notify /volume1/@ssh-notify/logs
chmod 700 /volume1/@ssh-notify/state

# 2. 돌던 감지 장치를 멈추고 새로 띄운다. 감시 시작 알림의 이유는 '설치'다.
if ! stop_detector; then
    echo "돌던 감지 장치를 멈추지 못했다. 새 파일은 다음 시작부터 쓰인다."
    exit 1
fi
LOG=/volume1/@ssh-notify/logs/ssh-notify-$(date +%Y%m).log
BEFORE=$(cat "$LOG" 2>/dev/null | wc -l)
/usr/bin/python3 /volume1/@ssh-notify/ssh-notify.py --install || exit 1

# 3. 업로드 폴더를 지운다.
remove_upload_dir

# 4. 감시 시작 기록이 로그에 생길 때까지 최대 50초 기다린다 (전송은 최대 3번, 한 번에 10초).
i=0
while [ "$i" -lt 50 ]; do
    sleep 1
    i=$((i + 1))
    NEW=$(tail -n +"$((BEFORE + 1))" "$LOG" 2>/dev/null | grep -E 'kind=start|^[0-9-]+ [0-9:]+ error ' | tail -n 1)
    if [ -n "$NEW" ]; then
        echo "로그: $NEW"
        case "$NEW" in
        *" sent kind=start "*)
            echo "설치했다. 디스코드에 '설치' 감시 시작 알림이 왔는지 본다."
            exit 0
            ;;
        *)
            echo "감시 시작 알림을 보내지 못했다. README 의 '문제 해결'을 본다."
            exit 1
            ;;
        esac
    fi
done
echo "50초 안에 로그에 감시 시작 기록이 없다. $LOG 를 본다."
exit 1
