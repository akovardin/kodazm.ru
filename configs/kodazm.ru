server {
    listen       80;
    server_name  4gophers.ru;

    return 301 $scheme://kodazm.ru$request_uri;
}

server {
    listen       80;
    server_name  4gophers.com;

    return 301 $scheme://kodazm.ru$request_uri;
}

# server {
#     listen       80;
#     server_name  kodazm.ru;

#     root /var/www/kodazm/www/public;

#     location / {
#         try_files $uri $uri/ =404;
#     }

#     location ~ /.well-known {
#         allow all;
#     }
# }

server {
    listen 80;
    listen [::]:80;

    server_name kodazm.ru;
    # редирект на HTTPS
    return 301 https://$server_name$request_uri;

    server_tokens off;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    server_name kodazm.ru;

    ssl_certificate /etc/letsencrypt/live/kodazm.ru/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/kodazm.ru/privkey.pem;
    # ssl_dhparam /etc/ssl/certs/dhparam.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;
    # конфигурация Modern
    ssl_protocols TLSv1.2;
    ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256';
    ssl_prefer_server_ciphers on;
    # HSTS - форсированно устанавливать соединение по HTTPS
    add_header Strict-Transport-Security "max-age=15768000";
    # Разрешение прикрепления OCSP-ответов сервером
    ssl_stapling on;
    # Разрешение проверки сервером ответов OCSP
    ssl_stapling_verify on;

    root /var/www/kodazm/www/public;
    index index.html index.htm index.nginx-debian.html;
    # Запрещение выдачи версии nginx в HTTP-заголовках
    server_tokens off;

    location / {
        try_files $uri $uri/ =404;
    }
    # для валидации Let's Encrypt
    location ~ /.well-known {
        allow all;
    }
}