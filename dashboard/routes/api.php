<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\ReceiveDataController;
use App\Http\Controllers\Api\ControlQueueController;

/*
|--------------------------------------------------------------------------
| API Routes
|--------------------------------------------------------------------------
|
| Here is where you can register API routes for your application. These
| routes are loaded by the RouteServiceProvider within a group which
| is assigned the "api" middleware group. Enjoy building your API!
|
*/

Route::middleware('auth:sanctum')->get('/user', function (Request $request) {
    return $request->user();
});

/*
|--------------------------------------------------------------------------
| SmartPonic ESP32 Endpoints
|--------------------------------------------------------------------------
|
| These use HMAC-based authentication (not Laravel's built-in auth).
| No CSRF or Sanctum middleware — the HMAC signature in headers is
| verified inside the controller.
|
*/

Route::post('/receive-data', ReceiveDataController::class);
Route::post('/control-queue', ControlQueueController::class);
