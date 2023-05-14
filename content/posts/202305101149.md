---
title: "Docker Composeで楽にPterodactylをセットアップ"
date: 2023-05-10T11:49:38+09:00
draft: false
tags: [ minecraft, docker ]
---

[Pterodactyl](https://pterodactyl.io/)というMinecraftサーバーを始めとしたゲームサーバーを便利なWeb上のUIで管理できるソフトウェアがあります。
Pterodactylは各ゲームサーバーをDockerコンテナ上で動作させるアーキテクチャになっており、ローカルの環境に依存せずに運用できるので大変便利なのですが、[公式ドキュメント](https://pterodactyl.io/panel/1.0/getting_started.html)を見るとPterodactyl本体のセットアップが少々大変そうです。
そこで、Pterodactyl自体もDocker Composeを用いてDockerコンテナとして簡単にセットアップできるようにしていきます。

## 環境

- Debian GNU/Linux 11
- Docker 20.10.18
- Docker Compose v2.10.2

## Pterodactylのアーキテクチャについて

Pterodactylはゲームサーバーの管理用UIを提供するPanelと、ゲームサーバーのコンテナを管理するWingsから構成されています。
PanelとWingsは別ホストで動かすこともできるのですが、私の用途では同じマシンですべて稼働させたかったので、同一ホストでのセットアップを紹介していきます。

## Docker Composeでデプロイ

実はPterodactyl公式もDockerでのセットアップも想定しているようで、[GitHubのリポジトリ](https://github.com/pterodactyl/panel)を見ると `docker-compose.yml` がしれっと置いてあったりします。
これを拝借して、単一の `docker-compose.yml` でPanelとWings、その他データベース類もデプロイできるようにしたものが下になります。

```yaml
version: "3.8"

x-common:
  database:
    &db-environment
    MYSQL_PASSWORD: &db-password "CHANGE_ME"
    MYSQL_ROOT_PASSWORD: "CHANGE_ME_TOO"
  panel:
    &panel-environment
    APP_URL: "http://ホストのローカルIPアドレス:8888"
    APP_TIMEZONE: "Asia/Tokyo"
    APP_SERVICE_AUTHOR: "noreply@example.com"
  mail:
    &mail-environment
    MAIL_FROM: "noreply@example.com"
    MAIL_DRIVER: "smtp"
    MAIL_HOST: "mail"
    MAIL_PORT: "1025"
    MAIL_USERNAME: ""
    MAIL_PASSWORD: ""
    MAIL_ENCRYPTION: "true"

services:
  database:
    image: mariadb:10.5
    restart: always
    command: --default-authentication-plugin=mysql_native_password
    volumes:
      - "./srv-pterodactyl/database:/var/lib/mysql"
    environment:
      <<: *db-environment
      MYSQL_DATABASE: "panel"
      MYSQL_USER: "pterodactyl"
  cache:
    image: redis:alpine
    restart: always
  panel:
    image: ghcr.io/pterodactyl/panel:latest
    restart: always
    ports:
      - "8888:80"
    links:
      - database
      - cache
    volumes:
      - "./srv-pterodactyl/var/:/app/var/"
      - "./srv-pterodactyl/nginx/:/etc/nginx/http.d/"
      - "./srv-pterodactyl/certs/:/etc/letsencrypt/"
      - "./srv-pterodactyl/logs/:/app/storage/logs"
    environment:
      <<: [*panel-environment, *mail-environment]
      DB_PASSWORD: *db-password
      APP_ENV: "production"
      APP_ENVIRONMENT_ONLY: "false"
      CACHE_DRIVER: "redis"
      SESSION_DRIVER: "redis"
      QUEUE_DRIVER: "redis"
      REDIS_HOST: "cache"
      DB_HOST: "database"
      DB_PORT: "3306"
  wings:
    image: ghcr.io/pterodactyl/wings:latest
    restart: always
    ports:
      - "8080:8080"
      - "2022:2022"
    tty: true
    environment:
      TZ: "Asia/Tokyo"
      WINGS_UID: 988
      WINGS_GID: 988
      WINGS_USERNAME: pterodactyl
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "/var/lib/docker/containers/:/var/lib/docker/containers/"
      - "./etc-pterodactyl/:/etc/pterodactyl/"
      - "/var/lib/pterodactyl/:/var/lib/pterodactyl/"
      - "./var-log-pterodactyl/:/var/log/pterodactyl/"
      - "/tmp/pterodactyl/:/tmp/pterodactyl/"
      - "./etc-ssl-certs:/etc/ssl/certs:ro"

networks:
  default:
    ipam:
      config:
        - subnet: 172.20.0.0/16
```

### ボリュームのマウントに関する注意点

Wingsがゲームサーバーのコンテナを作成する際、`/var/lib/pterodactyl/volumes` 配下のディレクトリを絶対パスで指定してボリュームとしてマウントします。
ここで絶対パスを解釈するのはホスト側で動いているDockerデーモンなので、ホスト側でもゲームサーバーのボリュームを `/var/lib/pterodactyl/volumes` 配下に配置する必要があります。
`/var/lib/pterodactyl` のマウントでホストとコンテナでパスを一致させているのはこのためです。

### ネットワークに関する注意点

Wingsはデフォルトの設定で、ゲームサーバーのコンテナを所属させるネットワークとして `172.0.18.0/16` を作成しようとするので、このネットワークが既に存在していると起動に失敗します。

### デプロイとWingsの設定

下記のコマンドで `docker-compose.yml` の内容をデプロイします。

```sh
cd pterodactyl/ # docker-compose.ymlがあるディレクトリ
docker compose up -d
```

しばらく待つとデータベース等のセットアップが終わり、 `http://ホストのローカルIPアドレス:8888` でWebの管理画面にアクセスできるはずです。

次に、[公式ドキュメント](https://pterodactyl.io/panel/1.0/getting_started.html#add-the-first-user)を参考にして、Panelコンテナ内のコマンドを実行してユーザーのセットアップを行います。

```sh
docker compose exec panel php artisan p:user:make
```

作成したユーザーでログインができたら、管理者用画面 (歯車マーク) で `Location` を作成した後に `Node` を作成します。
ここで作成した `Node` の `Configuration` タブにある内容を、 `config.yml` としてWingsコンテナ内の `/etc/pterodactyl` 配下にマウントされるように配置します (上記の例ではホストの `./etc-pterodactyl` 配下) 。

最後にWingsコンテナを再起動すると設定が反映され、管理画面からWingsと通信できているのが確認できるはずです。

```sh
docker compose restart wings
```

## まとめ

Dockerコンテナを制御するプロセスをDockerコンテナ内で動かす、ということをしたので注意点はいくつかありましたが、やはりDocker Composeだけでセットアップが完了するのは便利ですね。

今回はローカル環境向けのPterodactylセットアップの紹介でしたが、気が向いたら本番環境向けにSSL化などの手順も含めたセットアップについての記事も書こうと思います。
