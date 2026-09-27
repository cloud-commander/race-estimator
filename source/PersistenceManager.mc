using Toybox.Lang;
using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.System;

// Manages persistent storage with validation and corruption detection
// Handles save/load operations with checksum verification.
// Saves are only triggered by milestone events (a handful per activity), so
// there is deliberately no throttle: a throttled save would silently drop state.
class PersistenceManager {

  // Storage keys
  private const STORAGE_KEY_FINISH_TIMES = "finishTimesMs";
  private const STORAGE_KEY_CHECKSUM = "checksum";

  // Validation constants
  private const CHECKSUM_PRIME = 31;  // Standard hash prime
  private const MAX_FINISH_TIME_MS = 86400000;  // 24 hours max per milestone (sanity check)

  // Debug logging
  private var mDebugLogging as Lang.Boolean = false;

  /**
   * Initialize persistence manager
   * @param debugLogging Enable verbose logging
   */
  function initialize(debugLogging as Lang.Boolean) {
    mDebugLogging = debugLogging;
  }

  /**
   * Save milestone finish times to persistent storage
   * Includes checksum for corruption detection
   * @param finishTimesMs Array of finish times to save
   * @return true if saved, false on storage error
   */
  public function saveFinishTimes(
    finishTimesMs as Lang.Array<Lang.Number?>
  ) as Lang.Boolean {
    var checksum = calculateChecksum(finishTimesMs);

    try {
      Storage.setValue(
        STORAGE_KEY_FINISH_TIMES,
        finishTimesMs as Lang.Array<Application.PropertyValueType>
      );
      Storage.setValue(STORAGE_KEY_CHECKSUM, checksum);

      if (mDebugLogging) {
        System.println("PersistenceManager: Saved " + finishTimesMs.size() +
                       " finish times (checksum=" + checksum + ")");
      }

      return true;

    } catch (ex) {
      System.println("PersistenceManager: ERROR saving to storage: " + ex.getErrorMessage());
      return false;
    }
  }

  /**
   * Load milestone finish times from persistent storage
   * Validates data integrity using checksum
   * @param expectedSize Expected array size for validation
   * @return Array of finish times, or null if invalid/corrupted
   */
  public function loadFinishTimes(expectedSize as Lang.Number) as Lang.Array<Lang.Number?>? {
    try {
      var storedTimes = Storage.getValue(STORAGE_KEY_FINISH_TIMES);
      var storedChecksum = Storage.getValue(STORAGE_KEY_CHECKSUM);

      if (storedTimes == null) {
        if (mDebugLogging) {
          System.println("PersistenceManager: No stored data found");
        }
        return null;
      }

      // Validate data integrity
      if (!validateStoredData(storedTimes, storedChecksum, expectedSize)) {
        System.println("PersistenceManager: Stored data validation failed - ignoring");
        return null;
      }

      // Type-safe cast after validation
      var timesArray = storedTimes as Lang.Array<Lang.Number?>;

      if (mDebugLogging) {
        System.println("PersistenceManager: Loaded " + timesArray.size() +
                       " finish times (checksum valid)");
      }

      return timesArray;

    } catch (ex) {
      System.println("PersistenceManager: ERROR loading from storage: " + ex.getErrorMessage());
      return null;
    }
  }

  /**
   * Clear all stored data
   * @return true if successful
   */
  public function clearStorage() as Lang.Boolean {
    try {
      Storage.deleteValue(STORAGE_KEY_FINISH_TIMES);
      Storage.deleteValue(STORAGE_KEY_CHECKSUM);

      if (mDebugLogging) {
        System.println("PersistenceManager: Storage cleared");
      }

      return true;

    } catch (ex) {
      System.println("PersistenceManager: ERROR clearing storage: " + ex.getErrorMessage());
      return false;
    }
  }

  /**
   * Validate stored data integrity and structure
   * @param storedTimes Array from storage
   * @param storedChecksum Checksum from storage
   * @param expectedSize Expected array size
   * @return true if data is valid
   */
  private function validateStoredData(
    storedTimes as Application.PropertyValueType,
    storedChecksum as Application.PropertyValueType,
    expectedSize as Lang.Number
  ) as Lang.Boolean {

    // Type validation
    if (!(storedTimes instanceof Lang.Array)) {
      if (mDebugLogging) {
        System.println("PersistenceManager: Validation failed - not an array");
      }
      return false;
    }

    var timesArray = storedTimes as Lang.Array<Lang.Number?>;

    // Size validation
    if (timesArray.size() != expectedSize) {
      if (mDebugLogging) {
        System.println("PersistenceManager: Validation failed - size mismatch (" +
                       timesArray.size() + " vs expected " + expectedSize + ")");
      }
      return false;
    }

    // Checksum validation (if checksum was stored)
    if (storedChecksum instanceof Lang.Number) {
      var calculatedChecksum = calculateChecksum(timesArray);
      var storedChecksumNum = storedChecksum as Lang.Number;
      if (storedChecksumNum != calculatedChecksum) {
        if (mDebugLogging) {
          System.println("PersistenceManager: Validation failed - checksum mismatch (" +
                         storedChecksumNum + " vs " + calculatedChecksum + ")");
        }
        return false;
      }
    }

    // Content validation - check each finish time is reasonable
    for (var i = 0; i < timesArray.size(); i++) {
      var time = timesArray[i];
      if (time != null) {
        if (time < 0 || time > MAX_FINISH_TIME_MS) {
          if (mDebugLogging) {
            System.println("PersistenceManager: Validation failed - invalid time at index " + i +
                           " (value=" + time + ")");
          }
          return false;
        }

        // Milestone times should be monotonically increasing
        var prev = i > 0 ? timesArray[i - 1] : null;
        if (prev != null && time < prev) {
          if (mDebugLogging) {
            System.println("PersistenceManager: Validation failed - non-monotonic times at index " + i);
          }
          return false;
        }
      }
    }

    return true;
  }

  /**
   * Calculate checksum for data integrity verification
   * Uses simple polynomial rolling hash
   * @param finishTimesMs Array to checksum
   * @return Checksum value
   */
  private function calculateChecksum(finishTimesMs as Lang.Array<Lang.Number?>) as Lang.Number {
    var hash = 0;

    for (var i = 0; i < finishTimesMs.size(); i++) {
      var value = finishTimesMs[i];
      if (value != null) {
        // Polynomial rolling hash: hash = hash * prime + value
        hash = hash * CHECKSUM_PRIME + value;
      } else {
        // Include nulls in hash to detect position changes
        hash = hash * CHECKSUM_PRIME;
      }
    }

    return hash;
  }
}
