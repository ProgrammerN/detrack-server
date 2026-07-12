/*
 * Copyright 2026 Detrack
 *
 * Thrown when a notification cannot be delivered because the recipient has not
 * registered a device token yet (or tokens are expired). Callers should treat
 * this as a skip, not a server failure.
 */
package org.traccar.notification;

public class NotificationSkippedException extends MessageException {

    public NotificationSkippedException(String message) {
        super(message);
    }

}
