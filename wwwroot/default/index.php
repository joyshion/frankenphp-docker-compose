<?php

// FrankenPHP Worker 模式入口文件

// 初始化代码（只执行一次）
$startTime = microtime(true);
$workerPid = getmypid();
$requestCount = 0;

echo "Worker initialized (PID: {$workerPid})\n";

// Worker 主循环
while (frankenphp_handle_request(function() use (&$requestCount, $startTime, $workerPid) {
    $requestCount++;
    $uptime = round(microtime(true) - $startTime, 2);
    
    // 获取请求信息
    $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
    $uri = $_SERVER['REQUEST_URI'] ?? '/';
    $userAgent = $_SERVER['HTTP_USER_AGENT'] ?? 'Unknown';
    
    // 设置响应头
    header('Content-Type: text/html; charset=utf-8');
    
    // 路由处理
    switch ($uri) {
        case '/':
            echo "<h1>Hello from FrankenPHP 版本 Worker!</h1>";
            echo "<p><strong>Worker PID:</strong> {$workerPid}</p>";
            echo "<p><strong>Request Count:</strong> {$requestCount}</p>";
            echo "<p><strong>Uptime:</strong> {$uptime} seconds</p>";
            echo "<p><strong>Current Time:</strong> " . date('Y-m-d H:i:s') . "</p>";
            echo "<hr>";
            echo "<p>Try visiting:</p>";
            echo "<ul>";
            echo "<li><a href='/test'>Test Page</a></li>";
            echo "<li><a href='/api'>API Endpoint</a></li>";
            echo "<li><a href='/info'>System Info</a></li>";
            echo "</ul>";
            break;
            
        case '/test':
            echo "<h1>Test Page</h1>";
            echo "<p>This is request #{$requestCount} handled by worker {$workerPid}</p>";
            echo "<p><a href='/'>← Back to Home</a></p>";
            break;
            
        case '/api':
            header('Content-Type: application/json');
            echo json_encode([
                'status' => 'ok',
                'worker_pid' => $workerPid,
                'request_count' => $requestCount,
                'uptime' => $uptime,
                'timestamp' => time(),
                'method' => $method,
                'uri' => $uri
            ], JSON_PRETTY_PRINT);
            break;
            
        case '/info':
            phpinfo();
            echo "<p><a href='/'>← Back to Home</a></p>";
            break;
            
        default:
            http_response_code(404);
            echo "<h1>404 - Page Not Found</h1>";
            echo "<p>The requested page '{$uri}' was not found.</p>";
            echo "<p><a href='/'>← Back to Home</a></p>";
            break;
    }
    
    // 输出请求日志
    error_log("Worker {$workerPid}: {$method} {$uri} - Request #{$requestCount}");
    
})) {
    // 这里可以添加请求之间的清理代码
    // 例如重置全局变量、清理缓存等
}

// Worker 退出时的清理代码
echo "Worker {$workerPid} is shutting down after handling {$requestCount} requests\n";


