# GEMINI.md

## Project Overview

This project is a Garmin Connect IQ data field called **Race Estimator**. It provides real-time finish time predictions for nine different running milestones (5K, 10K, half marathon, etc.). The data field is optimized for performance, memory usage, and battery life on Garmin devices, with special considerations for AMOLED screens to prevent burn-in.

The application is written in **Monkey C**. The manifest declares `minApiLevel="5.0.0"`, but the source uses modern Monkey C features (nullable types, Double literals). Recommended development SDK: 5.2.0+.

The architecture is based on the standard Connect IQ data field structure:

- `RaceEstimatorApp.mc`: The main application class that handles the application lifecycle.
- `RaceEstimatorView.mc`: The data field view, which contains the core logic for:
  - Calculating race predictions using an Exponential Moving Average (EMA) for pace smoothing.
  - Rendering the data field, including the predictions and a progress arc.
  - Handling user input and activity data.
  - Managing application state and storage.

The project also includes a suite of scripts for testing and validation, as well as detailed documentation on the design and implementation of the data field.

## Building and Running

### Building the Project

The project is built using the `monkeyc` compiler, which is part of the Garmin Connect IQ SDK. The build process is configured using the `monkey.jungle` file.

To build the project for a specific device (e.g., fenix7), run the following command:

```bash
monkeyc -o bin/RaceEstimator.prg -f monkey.jungle \
  -y <path_to_your_developer_key> -d fenix7
```

### Running the Data Field

To run the data field, you need to side-load the generated `.prg` file to your Garmin device.

1.  Connect your Garmin device to your computer.
2.  Copy the `.prg` file to the `GARMIN/Apps` directory on your device.
3.  On your device, add the "Race Estimator" data field to a running activity screen.

You can also use the Garmin Connect IQ Simulator to run and test the data field without a physical device.

### Testing

The project includes several scripts for testing and validation:

- `scripts/analyze_fit.py`: Analyzes a `.fit` file and compares the results with the data field's calculations.
- `scripts/validate_fit_anomaly_detection.py`: A validation suite for the FIT anomaly detection feature.

To run the Python scripts, you will need to install the `fitparse` library:

```bash
pip install fitparse
```

## Development Conventions

### Coding Style

The project follows the standard Monkey C coding conventions. Key aspects of the coding style include:

- **Clarity and Readability:** The code is well-commented, with clear variable and function names.
- **Performance:** The code is optimized for performance, with a focus on minimizing memory allocations and CPU usage in the `compute()` and `onUpdate()` hot paths.
- **Defensive Programming:** The code includes numerous checks to handle potential errors and invalid data.

### Testing Practices

The project has a strong focus on testing and validation. The `scripts` directory contains tools for analyzing activity data and validating the accuracy of the predictions. The `docs` directory contains detailed analysis of test results.

### Contribution Guidelines

When contributing to the project, please follow these guidelines:

- Adhere to the existing coding style and conventions.
- Avoid dynamic allocations in `compute()` and `onUpdate()`.
- Gate debug `System.println()` logs behind a `DEBUG` flag.
- Test changes on both MIP and AMOLED devices.
- Keep `STORAGE_VERSION` in sync when changing the storage schema.
