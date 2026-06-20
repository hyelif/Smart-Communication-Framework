<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\DashboardController;
use App\Http\Controllers\ExportController;
use App\Http\Controllers\TelegramController;

Route::get("/", [DashboardController::class, "index"]);
Route::get("/api/dashboard/poll", [DashboardController::class, "poll"]);
Route::get("/api/dashboard/sensor-trends", [DashboardController::class, "sensorTrends"]);
Route::get("/api/dashboard/signal-history", [DashboardController::class, "signalHistory"]);
Route::get("/api/dashboard/analytics", [DashboardController::class, "analytics"]);
Route::get("/api/dashboard/system-summary", [DashboardController::class, "systemSummary"]);
Route::get("/api/dashboard/node-sensors", [DashboardController::class, "nodeSensors"]);
Route::get("/api/dashboard/clear-cache", [DashboardController::class, "clearCache"]);
Route::get("/api/dashboard/export", [ExportController::class, "export"]);
Route::get("/api/dashboard/export-summary", [ExportController::class, "summaryExport"]);
Route::get("/api/health", function () {
    try {
        $turso = app(\App\Services\TursoService::class);
        $healthy = $turso->health();
        return response()->json([
            "status" => $healthy ? "ok" : "error",
            "database" => $healthy ? "connected" : "disconnected",
        ]);
    } catch (\Exception $e) {
        return response()->json(["status" => "error", "database" => $e->getMessage()], 500);
    }
});

Route::prefix("/api/telegram")->group(function () {
    Route::get("/status", [TelegramController::class, "status"]);
    Route::post("/start", [TelegramController::class, "start"]);
    Route::post("/stop", [TelegramController::class, "stop"]);
});
