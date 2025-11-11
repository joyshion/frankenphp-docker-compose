# FrankenPHP + Caddy + MySQL + Redis

本项目提供一个使用 FrankenPHP Worker 模式、Caddy 作为前端服务器，并集成MySQL和Redis的应用容器开发示例。

## 目录结构概览

- [docker-compose.yaml](docker-compose.yaml): 编排 Caddy / FrankenPHP / MySQL / Redis
- [caddy/Caddyfile](caddy/Caddyfile): 主站点与虚拟主机配置
- [wwwroot/default/index.php](wwwroot/default/index.php): FrankenPHP Worker 模式入口示例（含简单路由、统计）

## 运行

```sh
docker compose up -d
```

启动后：
- 访问根路径 `localhost` 可查看 Worker 信息
- `/test` 测试页
- `/api` 返回 JSON
- `/info` 输出 phpinfo

## FrankenPHP Worker 说明

示例入口文件位于 [wwwroot/default/index.php](wwwroot/default/index.php)，使用 `frankenphp_handle_request` 循环保持进程常驻并统计：
- 请求计数
- 运行时长
- Worker PID

## 集成 Laravel

### 创建 Laravel 项目

在`wwwroot`目录下创建一个 Laravel 项目，并执行安装：

```sh
cd wwwroot
composer create-project laravel/laravel:^12.0 laravel
cd laravel
cp .env.example .env
php artisan key:generate
```

### 普通模式

编辑 [caddy/Caddyfile](caddy/Caddyfile), 配置Laravel站点：
```caddyfile
laravel.localhost:80 {
    root * /wwwroot/laravel/public
    php_server
    file_server
}
```

### Worker模式

安装 [Laravel Octane](https://laravel.com/docs/12.x/octane)
```shell
composer require laravel/octane
php artisan octane:install --server=frankenphp
```

编辑 [caddy/Caddyfile](caddy/Caddyfile), 配置Laravel站点：
```caddyfile
laravel.localhost:80 {
    root * /wwwroot/laravel/public
    php_server {
        worker /wwwroot/laravel/public/frankenphp-worker.php
    }
    file_server
}
```
