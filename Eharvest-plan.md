# NFC Power Latch & LED Control System (ESP32 + ST25DV16K)

This project implements a hardware-based power latching circuit that allows a mobile app to turn an ESP32 completely ON or OFF using an ST25DV16K NFC Dynamic Tag. A single standalone physical button remains dedicated strictly to controlling an LED during normal operation.

## 📦 Bill of Materials (Components Needed)

### Microcontrollers & Modules
* **1x** ESP32 Development Board (e.g., ESP32-WROOM-32E)
* **1x** ST25DV16K I2C RFID Dynamic Tag Board (with `VEH` and `GPO` pins broken out)
* **1x** Compatible NFC Antenna (usually included with the ST25DV module)

### Power Switching Logic
* **1x** 74LVC74 (or CD4013) Dual D-Flip-Flop IC
* **1x** AO3401 (or IRF9540) P-Channel MOSFET 
* **1x** 2N7000 (or AO3400) N-Channel MOSFET

### User Interface
* **1x** Momentary Push Button (for LED control)
* **1x** Standard LED 

### Passives & Accessories
* **3x** 10kΩ Resistors (Pull-up/Pull-down protection)
* **1x** 330Ω Resistor (LED safety protector)
* **1x** 0.1µF Ceramic Capacitor (Noise filter)
* **1x** Breadboard & Jumper Wires
* **1x** Main Power Supply (5V USB or 3.7V Battery)

---

## 🔌 Wiring Plan & Pin Connections

### Step 1: Continuous Main Power (Always Alive)
These components must stay powered directly from the main source (`VCC` and `GND`) so they can listen for the phone tap when the ESP32 is powered off.
* Connect **ST25DV VCC** ──► Main VCC
* Connect **74LVC74 VCC (Pin 14)** ──► Main VCC
* Connect **ST25DV GND** ──► Main GND
* Connect **74LVC74 GND (Pin 7)** ──► Main GND

### Step 2: NFC Trigger & Flip-Flop Configuration
Configures the Flip-Flop chip to operate in a "toggle" mode, changing its electrical output state every time the NFC tag harvests an RF power pulse.
* Connect **ST25DV VEH** (Energy Harvest) ──► **74LVC74 CLK (Pin 3)**
* Connect **74LVC74 Q̄ / Inverted Output (Pin 6)** ──► **74LVC74 D / Data Input (Pin 2)**
* Connect a **10kΩ resistor** from Main VCC ──► **74LVC74 SET (Pin 4)** *(Keeps SET disabled)*
* Connect a **10kΩ resistor** from Main GND ──► **74LVC74 CLR / Reset (Pin 1)** *(Keeps CLR stable)*

### Step 3: The Power Gate (MOSFET Switch)
Allows the Flip-Flop to safely open and close the heavy power line feeding the ESP32.
* Connect **74LVC74 Q / True Output (Pin 5)** ──► **N-Channel MOSFET Gate**
* Connect **N-Channel MOSFET Source** ──► Main GND
* Connect **N-Channel MOSFET Drain** ──► **P-Channel MOSFET Gate**
* Connect a **10kΩ resistor** from Main VCC ──► **P-Channel MOSFET Gate** *(Forces power OFF by default)*
* Connect **P-Channel MOSFET Source** ──► Main VCC
* Connect **P-Channel MOSFET Drain** ──► **ESP32 5V (or 3V3) Power Pin**
* Connect **ESP32 GND** ──► Main GND

### Step 4: Intelligent Data & Shutdown Links (Method B)
Establishes the communication pathways between the running ESP32 and the NFC tag, enabling a data-driven shutdown.
* Connect **ST25DV SDA** ──► **ESP32 GPIO 21** (I2C Data)
* Connect **ST25DV SCL** ──► **ESP32 GPIO 22** (I2C Clock)
* Connect **ST25DV GPO** ──► **ESP32 GPIO 19** (Alerts ESP32 when a phone is tapping)
* Connect **ESP32 GPIO 5** ──► **74LVC74 CLR / Reset (Pin 1)** *(The safe shutdown trigger)*

### Step 5: Isolated Button & LED Control
These are wired directly to the ESP32 and only activate when the main power gate is flipped open.
* Connect **Push Button (Pin 1)** ──► **ESP32 GPIO 4**
* Connect **Push Button (Pin 2)** ──► **ESP32 GND**
* Connect **ESP32 GPIO 2** ──► **330Ω Resistor** ──► **LED Anode (+)**
* Connect **LED Cathode (-)** ──► **ESP32 GND**

---

## 🧠 System Architecture Overview

### 1. Booting Up (Turning ON)
1. The phone taps the antenna. 
2. The ST25DV16K collects the ambient RF energy and outputs a voltage pulse on `VEH`.
3. This pulse sets the **74LVC74 Flip-Flop** to high.
4. The Flip-Flop turns on the MOSFET power gate, allowing battery power to boot up the ESP32.

### 2. Normal Operation
* The ESP32 handles the physical button press to switch the LED state. 
* This is completely isolated from the power system, ensuring button clicks never accidentally trigger a system shutdown.

### 3. Safe Shutdown (Turning OFF via App)
1. The mobile app writes a `"SHUTDOWN"` data command into the ST25DV16K memory mailbox.
2. The ST25DV16K pulses the `GPO` pin to tell the ESP32 it has mail.
3. The ESP32 reads the message over the I2C wires (`SDA`/`SCL`).
4. The ESP32 safely finishes its current tasks and then sends a `HIGH` signal out of **GPIO 5** directly into the **74LVC74 Reset line (Pin 1)**.
5. The Flip-Flop cuts the MOSFET gate, dropping system power down to absolute zero.
