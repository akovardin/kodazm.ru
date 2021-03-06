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

server {
    listen       80;
    server_name  kodazm.ru;

    location / {
        root   /var/www/kodazm/www/public;
    }

    location ~ /.well-known {
        allow all;
    }
}
