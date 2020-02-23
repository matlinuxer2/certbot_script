#!/usr/bin/env bash
# author: Chun-Yu Lee (Mat) <matlinuxer2@gmail.com>

SELF_EXE=$(readlink -f $0)
ROOT_DIR=$(dirname $SELF_EXE)
ROOT_CFG="$ROOT_DIR/config.json"
ROOT_LOG="$ROOT_DIR/run.log"
DATA_DIR="$ROOT_DIR/persistent"
DOCKER_OPTS=""
CERTBOT_OPTS=""

function usage(){
        cat <<EOD
usage:
        $(basename $SELF_EXE) (certonly|certificates|link)

EOD
}

function die(){
    printf "$@\n"
    exit 1
}

function precheck(){
    [ -e "$ROOT_CFG" ] || die "[Err] $ROOT_CFG not found."

    jq type "$ROOT_CFG" >&/dev/null; [ $? -eq 4 ] && die "[Err] $ROOT_CFG syntax error."
}

function docker_certbot_cmd(){
    DOCKER_OPTS="$DOCKER_OPTS -v $DATA_DIR:/etc/letsencrypt"
    [ -n "$DEBUG" ] && DOCKER_OPTS="$DOCKER_OPTS -e DEBUG=$DEBUG"

    cmd="docker run -it --rm --name certbot $DOCKER_OPTS certbot/certbot $CERTBOT_OPTS $@"
    [ -n "$DEBUG" ] && echo "cmd: $cmd"
    eval "$cmd" 2>&1 | tee $ROOT_DIR/run.log
}

subcmd="$1"
precheck
case "$subcmd" in
    certonly)
        var_email=$(jq -r '.email' $ROOT_CFG)
        var_domain=$(jq -r '.domain' $ROOT_CFG)
        GANDI_APIKEY=$(jq -r '.GANDI_APIKEY' $ROOT_CFG)
        DNS_SERVERS=$(jq -r '.DNS_SERVERS[]' $ROOT_CFG | paste -sd, -)

        [ -n "$var_email" ] || die "$ROOT_CFG: 'email' not found"
        [ -n "$var_domain" ] || die "$ROOT_CFG: 'domain' not found"
        [ -n "$GANDI_APIKEY" ] || die "$ROOT_CFG: 'GANDI_APIKEY' not found"
        [ -n "$DNS_SERVERS" ] || die "$ROOT_CFG: 'DNS_SERVERS' not found"

        DOCKER_OPTS="$DOCKER_OPTS -v $ROOT_DIR/manual_hook:/usr/bin/manual_hook"
        DOCKER_OPTS="$DOCKER_OPTS -e GANDI_APIKEY=$GANDI_APIKEY"
        DOCKER_OPTS="$DOCKER_OPTS -e DNS_SERVERS=$DNS_SERVERS"
        CERTBOT_OPTS="$CERTBOT_OPTS --pre-hook 'apk add python3 bind-tools' "
        CERTBOT_OPTS="$CERTBOT_OPTS --manual"
        CERTBOT_OPTS="$CERTBOT_OPTS --manual-auth-hook 'manual_hook auth' "
        CERTBOT_OPTS="$CERTBOT_OPTS --manual-cleanup-hook 'manual_hook cleanup' "
        CERTBOT_OPTS="$CERTBOT_OPTS --manual-public-ip-logging-ok"
        CERTBOT_OPTS="$CERTBOT_OPTS --preferred-challenges dns-01"

        HOST_UID=$(id -u)
        CERTBOT_OPTS="$CERTBOT_OPTS --post-hook 'chown $HOST_UID:$HOST_UID -R /etc/letsencrypt' "

        [ -n "$DRYRUN" ] && CERTBOT_OPTS="$CERTBOT_OPTS --dry-run"

        CERTBOT_OPTS="$CERTBOT_OPTS --agree-tos --no-eff-email"
        CERTBOT_OPTS="$CERTBOT_OPTS --noninteractive"
        CERTBOT_OPTS="$CERTBOT_OPTS --email $var_email"
        CERTBOT_OPTS="$CERTBOT_OPTS --cert-name $var_domain --domain $var_domain,*.$var_domain "

        docker_certbot_cmd $subcmd
    ;;

    certificates)
        docker_certbot_cmd $subcmd
    ;;

    link)
        var_domain=$(jq -r '.domain' $ROOT_CFG)
        [ -n "$var_domain" ] || die "$ROOT_CFG: 'domain' not found"

        function grab_cert_info(){
            local domainname="$1"
            $SELF_EXE certificates \
                | grep -A 4 -e "^\s*Certificate Name: $domainname" \
                | cat
        }

        tmpf=$(mktemp) && grab_cert_info $var_domain > $tmpf

        cert_txt=$(cat $tmpf | grep -e "Certificate Path:" | sed -e 's/.* Path:\s//g' -e 's/\s*$//g')
        priv_txt=$(cat $tmpf | grep -e "Private Key Path:" | sed -e 's/.* Path:\s//g' -e 's/\s*$//g')
        date_txt=$(cat $tmpf | grep -e "Expiry Date:" | sed -e 's/.* Date:\s//g' -e 's/\s*$//g')
        rm $tmpf

        if (echo $date_txt | grep -e '(VALID: .* days)' >& /dev/null) then
            (cd $DATA_DIR || exit
                ln -v -sf "${cert_txt#/etc/letsencrypt/}" "fullchain.pem"
                ln -v -sf "${priv_txt#/etc/letsencrypt/}" "privkey.pem"
            )
        else
            for item in "$DATA_DIR/fullchain.pem" "$DATA_DIR/privkey.pem"
            do
                    [ -e "$item" ] && rm -v "$item"
            done
        fi
    ;;

    *)
    usage
    ;;
esac
