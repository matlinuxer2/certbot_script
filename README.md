# Getting start

## 1. Add config.json

Add a config file `config.json`, content format like below:

```
{
        "APIKEY" : "########################",
        "email" : "someone@some.domain",
        "domain" : "your_domain.name",
        "type" : "gandi",
        "DNS_SERVERS": [
                "8.8.8.8",
                "1.1.1.1"
        ]
}
```

## 2. Get certificate

```
letsencrypt.sh certonly
```

## 3. Get and creat symbolic link

```
letsencrypt.sh link
```
