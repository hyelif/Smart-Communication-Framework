<?php
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');
header('Expires: 0');
?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SmartPonic Dashboard</title>
    <link rel="stylesheet" href="dashboard.css">
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
</head>
<body>
    <div class="shell">
        <header class="topbar">
            <div class="brand">
                <div class="mark">SP</div>
                <div>
                    <p class="eyebrow">Smart Communication Framework</p>
                    <h1>SmartPonic Dashboard</h1>
                    <p class="copy">Live telemetry, filtered export, health status, alerts, and calibration profiles.</p>
                </div>
            </div>
            <div class="actions">
                <select class="select" id="nodeSelect"></select>
                <div class="pill" id="generatedAt">Waiting for data...</div>
                <div class="pill" id="refreshStatus">Auto refresh every 15s</div>
                <button class="btn alt" id="refreshButton" type="button">Refresh Now</button>
            </div>
        </header>

        <nav class="tabs">
            <button class="tab active" data-tab="overview" type="button">Overview</button>
            <button class="tab" data-tab="trends" type="button">Trends</button>
            <button class="tab" data-tab="activity" type="button">Activity</button>
            <button class="tab" data-tab="health" type="button">Health</button>
            <button class="tab" data-tab="controls" type="button">Controls</button>
        </nav>

        <section class="paneltab active" data-panel="overview">
            <div class="hero">
                <article class="panel">
                    <div class="row spread top-align">
                        <div>
                            <p class="eyebrow">Node Telemetry</p>
                            <h2 id="heroTitle" class="hero-title">Node 1</h2>
                            <p class="copy" id="heroSubtitle">Loading live sensor history from dedicated sensor tables.</p>
                        </div>
                        <div class="badge" id="nodeStatusBadge"><span class="dot"></span><span>Waiting</span></div>
                    </div>
                    <div class="metrics">
                        <div class="metricbox"><p class="label">Location</p><p class="val" id="metricLocation">--</p></div>
                        <div class="metricbox"><p class="label">Configured Sensors</p><p class="val" id="metricSensors">0</p></div>
                        <div class="metricbox"><p class="label">RSSI</p><p class="val" id="metricRssi">--</p></div>
                        <div class="metricbox"><p class="label">SNR</p><p class="val" id="metricSnr">--</p></div>
                    </div>
                </article>

                <aside class="panel">
                    <p class="eyebrow">Snapshot</p>
                    <div class="summary">
                        <div class="mini">Latest Reading<strong id="snapshotTime">--</strong></div>
                        <div class="mini">Signal Quality<strong id="signalQualityCard">--</strong></div>
                        <div class="mini">Retention Policy<strong id="retentionSummary">--</strong></div>
                        <div class="mini">Active Alerts<strong id="alertCount">0</strong></div>
                    </div>
                </aside>
            </div>

            <section class="section">
                <div class="head">
                    <div>
                        <h2>Sensor Overview</h2>
                        <p class="copy">Adaptive cards for configured sensors on this node.</p>
                    </div>
                    <div class="pill" id="latestReading">No reading yet</div>
                </div>
                <div class="grid3" id="sensorGrid"></div>
            </section>

            <section class="section">
                <div class="head">
                    <div>
                        <h2>Communication Overview</h2>
                        <p class="copy">Adaptive reporting state, packet priority, location metadata, and analytics for this node.</p>
                    </div>
                </div>
                <div class="grid3">
                    <article class="panel compact-panel">
                        <p class="eyebrow">Latest Packet</p>
                        <div class="summary compact-summary">
                            <div class="mini">Priority<strong id="commPriority">--</strong></div>
                            <div class="mini">Report Mode<strong id="commReportMode">--</strong></div>
                            <div class="mini">Sequence<strong id="commSequence">--</strong></div>
                            <div class="mini">Distance<strong id="commDistance">--</strong></div>
                        </div>
                    </article>

                    <article class="panel compact-panel">
                        <p class="eyebrow">Location Metadata</p>
                        <div class="summary compact-summary single-column">
                            <div class="mini">Coordinates<strong id="commCoordinates">--</strong></div>
                            <div class="mini">Location Status<strong id="commLocationStatus">No synced location</strong></div>
                        </div>
                    </article>

                    <article class="panel compact-panel">
                        <p class="eyebrow">Signal Stats</p>
                        <div class="summary compact-summary">
                            <div class="mini">Avg RSSI<strong id="analyticsAvgRssi">--</strong></div>
                            <div class="mini">Avg SNR<strong id="analyticsAvgSnr">--</strong></div>
                            <div class="mini">Min RSSI<strong id="analyticsMinRssi">--</strong></div>
                            <div class="mini">Max RSSI<strong id="analyticsMaxRssi">--</strong></div>
                            <div class="mini">Packets<strong id="analyticsPktCount">--</strong></div>
                            <div class="mini">Report Interval<strong id="analyticsInterval">--</strong></div>
                        </div>
                    </article>

                    <article class="panel compact-panel">
                        <p class="eyebrow">Signal Quality Map</p>
                        <div class="map-container" id="signalMapContainer">
                            <div id="nodeMap" class="leaflet-map"></div>
                            <div class="signal-meter">
                                <span>RSSI</span>
                                <strong id="mapRssi">-- dBm</strong>
                                <span>SNR</span>
                                <strong id="mapSnr">-- dB</strong>
                            </div>
                        </div>
                    </article>
                </div>
            </section>
        </section>

        <section class="paneltab" data-panel="trends">
            <div class="panel">
                <div class="head">
                    <div>
                        <p class="eyebrow">Recent Sensor History</p>
                        <h2>Trend Graph</h2>
                    </div>
                    <div class="row">
                        <label class="pill" for="timeRangeSelect">Range</label>
                        <select class="select" id="timeRangeSelect">
                            <option value="1h">Last 1 hour</option>
                            <option value="6h">Last 6 hours</option>
                            <option value="24h" selected>Last 24 hours</option>
                            <option value="7d">Last 7 days</option>
                            <option value="30d">Last 30 days</option>
                        </select>
                        <div class="pill" id="chartInfo">Selected range</div>
                    </div>
                </div>
                <div class="stage">
                    <canvas id="trendChart"></canvas>
                    <div class="tip" id="chartTooltip"></div>
                </div>
                <div class="legend" id="chartLegend"></div>
            </div>

            <section class="section">
                <div class="head">
                    <div>
                        <h2>Trend Tables</h2>
                        <p class="copy">Three-per-row adaptive tables for the selected range.</p>
                    </div>
                </div>
                <div class="grid3" id="trendTableGrid"></div>
            </section>
        </section>

        <section class="paneltab" data-panel="activity">
            <div class="two">
                <div class="panel">
                    <div class="head">
                        <div>
                            <p class="eyebrow">Timeline</p>
                            <h2>Recent Activity</h2>
                        </div>
                    </div>
                    <div class="list" id="activityList"></div>
                </div>
                <div class="panel">
                    <div class="head">
                        <div>
                            <p class="eyebrow">Signal Trace</p>
                            <h2>Communication Trace</h2>
                        </div>
                    </div>
                    <div class="list signal-trace-list" id="signalList"></div>
                </div>
            </div>
        </section>

        <section class="paneltab" data-panel="health">
            <div class="two">
                <div class="panel">
                    <div class="head">
                        <div>
                            <p class="eyebrow">Device Health</p>
                            <h2>Node Health Monitoring</h2>
                            <p class="copy">Freshness, LoRa quality, and stale-packet detection.</p>
                        </div>
                    </div>
                    <div class="summary">
                        <div class="mini">Status<strong id="healthStatus">--</strong></div>
                        <div class="mini">Freshness<strong id="healthFreshness">--</strong></div>
                        <div class="mini">Signal Quality<strong id="healthSignal">--</strong></div>
                        <div class="mini">Priority / Mode<strong id="healthPriorityMode">--</strong></div>
                    </div>
                    <div class="health-details" id="healthDetails">
                        <div class="detail-item">
                            <span class="detail-label">Latest Sequence</span>
                            <strong id="healthSeq">--</strong>
                        </div>
                        <div class="detail-item">
                            <span class="detail-label">Latitude</span>
                            <strong id="healthLat">--</strong>
                        </div>
                        <div class="detail-item">
                            <span class="detail-label">Longitude</span>
                            <strong id="healthLon">--</strong>
                        </div>
                        <div class="detail-item">
                            <span class="detail-label">Distance</span>
                            <strong id="healthDist">--</strong>
                        </div>
                    </div>
                </div>

                <div class="panel">
                    <div class="head">
                        <div>
                            <p class="eyebrow">Communication Health</p>
                            <h2>Delivery &amp; Connectivity</h2>
                            <p class="copy">Packet delivery rate, sequence gaps, and link freshness.</p>
                        </div>
                    </div>
                    <div class="summary">
                        <div class="mini">Delivery Rate<strong id="commHealthRate">--</strong></div>
                        <div class="mini">Packets Received<strong id="commHealthReceived">--</strong></div>
                        <div class="mini">Sequence Gaps<strong id="commHealthGaps">--</strong></div>
                        <div class="mini">Last Packet<strong id="commHealthFresh">--</strong></div>
                    </div>
                </div>

                <div class="panel">
                    <div class="head">
                        <div>
                            <p class="eyebrow">Alerts</p>
                            <h2>Threshold Alerts</h2>
                            <p class="copy">Warnings from the latest values against your saved ranges.</p>
                        </div>
                    </div>
                    <div class="alerts" id="alertList"></div>
                </div>
            </div>
        </section>

        <section class="paneltab" data-panel="controls">
            <div class="controls">
                <section class="panel control-panel">
                    <p class="eyebrow">Data Controls</p>
                    <h3>Retention Setting</h3>
                    <p class="copy">Choose how long monitoring data should stay in the platform database.</p>
                    <div class="field">
                        <label class="label" for="retentionSelect">Data Retention</label>
                        <select class="select" id="retentionSelect">
                            <option value="keep_forever">Keep Forever</option>
                            <option value="30_days">Keep 30 Days</option>
                            <option value="90_days">Keep 90 Days</option>
                            <option value="1_year">Keep 1 Year</option>
                        </select>
                    </div>
                    <button class="btn" id="saveSettingsButton" type="button">Save Dashboard Settings</button>
                </section>

                <section class="panel control-panel">
                    <p class="eyebrow">Export</p>
                    <h3>Filtered Export</h3>
                    <p class="copy">Generate Excel or CSV exports by node, sensor type, or date window.</p>
                    <div class="field">
                        <label class="label" for="exportNodeSelect">Node</label>
                        <select class="select" id="exportNodeSelect"></select>
                    </div>
                    <div class="field">
                        <label class="label">Sensor Types</label>
                        <div class="checks" id="sensorTypeFilters"></div>
                    </div>
                    <div class="row">
                        <div class="field flex1">
                            <label class="label" for="exportDateFrom">Date From</label>
                            <input class="input" id="exportDateFrom" type="date">
                        </div>
                        <div class="field flex1">
                            <label class="label" for="exportDateTo">Date To</label>
                            <input class="input" id="exportDateTo" type="date">
                        </div>
                    </div>
                    <div class="row control-action-row">
                        <select class="select" id="exportFormatSelect">
                            <option value="excel">Excel Workbook</option>
                            <option value="csv">CSV</option>
                        </select>
                        <button class="btn" id="exportButton" type="button">Export Data</button>
                        <button class="btn alt" id="exportAllButton" type="button">Export All Data</button>
                    </div>
                </section>

                <section class="panel control-panel">
                    <p class="eyebrow">Snapshot</p>
                    <h3>Config Snapshot</h3>
                    <p class="copy">Export or import dashboard settings and sensor profiles as JSON.</p>
                    <div class="row control-action-row">
                        <button class="btn alt" id="exportConfigButton" type="button">Export Config JSON</button>
                        <button class="btn alt" id="importConfigButton" type="button">Import Config JSON</button>
                        <input class="hidden" id="configFileInput" type="file" accept=".json,application/json">
                    </div>
                </section>
            </div>

            <section class="section panel calibration-panel">
                <div class="head">
                    <div>
                        <p class="eyebrow">Calibration Management</p>
                        <h2>Sensor Thresholds and Calibration</h2>
                        <p class="copy">Set warning ranges and keep calibration coefficients ready for later Flutter sync.</p>
                    </div>
                    <button class="btn" id="saveProfilesButton" type="button">Save Sensor Profiles</button>
                </div>
                <div class="table-scroll">
                    <table class="profile">
                        <thead>
                            <tr>
                                <th>Sensor</th>
                                <th>Family</th>
                                <th>Min Alert</th>
                                <th>Max Alert</th>
                                <th>Calibration A</th>
                                <th>Calibration B</th>
                                <th>Calibration C</th>
                            </tr>
                        </thead>
                        <tbody id="profileTableBody"></tbody>
                    </table>
                </div>
            </section>
        </section>
    </div>

    <script src="dashboard_app.js"></script>
</body>
</html>
