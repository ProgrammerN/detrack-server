/*
 * Copyright 2016 - 2026 Anton Tananaev (anton@traccar.org)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.traccar.api.resource;

import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.traccar.api.ExtendedObjectResource;
import org.traccar.model.Event;
import org.traccar.model.ManagedUser;
import org.traccar.model.Notification;
import org.traccar.model.Typed;
import org.traccar.model.User;
import org.traccar.notification.MessageException;
import org.traccar.notification.NotificationSkippedException;
import org.traccar.notification.NotificationMessage;
import org.traccar.notification.NotificatorManager;
import org.traccar.storage.StorageException;
import org.traccar.storage.query.Columns;
import org.traccar.storage.query.Condition;
import org.traccar.storage.query.Request;

import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedList;
import java.util.Map;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

@Path("notifications")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class NotificationResource extends ExtendedObjectResource<Notification> {

    private static final Logger LOGGER = LoggerFactory.getLogger(NotificationResource.class);

    @Inject
    private NotificatorManager notificatorManager;

    public NotificationResource() {
        super(Notification.class, "description", List.of("description"));
    }

    @GET
    @Path("types")
    public Collection<Typed> get() {
        List<Typed> types = new LinkedList<>();
        Field[] fields = Event.class.getDeclaredFields();
        for (Field field : fields) {
            if (Modifier.isStatic(field.getModifiers()) && field.getName().startsWith("TYPE_")) {
                try {
                    types.add(new Typed(field.get(null).toString()));
                } catch (IllegalArgumentException | IllegalAccessException error) {
                    LOGGER.warn("Get event types error", error);
                }
            }
        }
        return types;
    }

    @GET
    @Path("notificators")
    public Collection<Typed> getNotificators(@QueryParam("announcement") boolean announcement) {
        Set<String> announcementsUnsupported = Set.of("command", "web");
        return notificatorManager.getAllNotificatorTypes().stream()
                .filter(typed -> !announcement || !announcementsUnsupported.contains(typed.type()))
                .collect(Collectors.toUnmodifiableSet());
    }

    @POST
    @Path("test")
    public Response testMessage() throws StorageException {
        User user = permissionsService.getUser(getUserId());
        Map<String, Object> results = new LinkedHashMap<>();
        int sent = 0;
        int skipped = 0;
        for (Typed method : notificatorManager.getAllNotificatorTypes()) {
            try {
                notificatorManager.getNotificator(method.type()).send(null, user, new Event("test", 0), null);
                results.put(method.type(), Map.of("sent", true));
                sent++;
            } catch (NotificationSkippedException exception) {
                results.put(method.type(), Map.of("skipped", true, "message", exception.getMessage()));
                skipped++;
                LOGGER.info("Test notification skipped via {} for user {} ({})",
                        method.type(), user.getId(), user.getEmail());
            } catch (MessageException exception) {
                results.put(method.type(), Map.of("failed", true, "message", exception.getMessage()));
                LOGGER.warn("Test notification failed via {}", method.type(), exception);
            }
        }
        return buildTestResponse(user, sent, skipped, results);
    }

    @POST
    @Path("test/{notificator}")
    public Response testMessage(@PathParam("notificator") String notificator) throws StorageException {
        User user = permissionsService.getUser(getUserId());
        try {
            notificatorManager.getNotificator(notificator).send(null, user, new Event("test", 0), null);
            return Response.noContent().build();
        } catch (NotificationSkippedException exception) {
            LOGGER.info("Test notification skipped via {} for user {} ({})",
                    notificator, user.getId(), user.getEmail());
            return skippedResponse(user, exception.getMessage());
        } catch (MessageException exception) {
            LOGGER.warn("Test notification failed via {}", notificator, exception);
            return Response.status(Response.Status.BAD_REQUEST).entity(exception.getMessage()).build();
        }
    }

    @POST
    @Path("send/{notificator}")
    public Response sendMessage(
            @PathParam("notificator") String notificator, @QueryParam("userId") List<Long> userIds,
            NotificationMessage message) throws StorageException {
        permissionsService.checkManager(getUserId());
        List<User> users;
        if (userIds.isEmpty()) {
            if (permissionsService.notAdmin(getUserId())) {
                users = storage.getObjects(User.class, new Request(new Columns.All(),
                        new Condition.Permission(User.class, getUserId(), ManagedUser.class).excludeGroups()));
            } else {
                users = storage.getObjects(User.class, new Request(new Columns.All()));
            }
        } else {
            users = new ArrayList<>();
            for (long userId : userIds) {
                var conditions = new LinkedList<Condition>();
                conditions.add(new Condition.Equals("id", userId));
                if (permissionsService.notAdmin(getUserId())) {
                    conditions.add(new Condition.Permission(
                            User.class, getUserId(), ManagedUser.class).excludeGroups());
                }
                users.add(storage.getObject(
                        User.class, new Request(new Columns.All(), Condition.merge(conditions))));
            }
        }

        int sent = 0;
        int skipped = 0;
        int failed = 0;
        List<Map<String, Object>> skippedUsers = new LinkedList<>();
        List<Map<String, Object>> failedUsers = new LinkedList<>();

        for (User user : users) {
            if (user == null || user.getTemporary()) {
                continue;
            }
            try {
                notificatorManager.getNotificator(notificator).send(user, message, null, null);
                sent++;
            } catch (NotificationSkippedException exception) {
                skipped++;
                skippedUsers.add(skippedUserEntry(user, exception.getMessage()));
                LOGGER.info("Notification skipped for user {} ({}) via {}: {}",
                        user.getId(), user.getEmail(), notificator, exception.getMessage());
            } catch (MessageException exception) {
                failed++;
                failedUsers.add(skippedUserEntry(user, exception.getMessage()));
                LOGGER.warn("Notification failed for user {} ({})", user.getId(), user.getEmail(), exception);
            }
        }

        if (sent > 0) {
            if (skipped > 0 || failed > 0) {
                LOGGER.info("Notification batch via {}: sent={}, skipped={}, failed={}",
                        notificator, sent, skipped, failed);
            }
            return Response.noContent().build();
        }

        Map<String, Object> body = new HashMap<>();
        body.put("sent", sent);
        body.put("skipped", skipped);
        body.put("failed", failed);
        if (!skippedUsers.isEmpty()) {
            body.put("skippedUsers", skippedUsers);
        }
        if (!failedUsers.isEmpty()) {
            body.put("failedUsers", failedUsers);
        }
        if (skipped > 0 && failed == 0) {
            body.put("message", "No recipients had a registered mobile push token. "
                    + "Users must open the Detrack app and sign in to receive push notifications.");
            return Response.status(Response.Status.CONFLICT).entity(body).build();
        }
        body.put("message", "Notification could not be delivered to any selected users.");
        return Response.status(Response.Status.BAD_REQUEST).entity(body).build();
    }

    private static Response buildTestResponse(
            User user, int sent, int skipped, Map<String, Object> results) {
        if (sent > 0 && skipped == 0) {
            return Response.noContent().build();
        }
        Map<String, Object> body = new HashMap<>();
        body.put("userId", user.getId());
        body.put("email", user.getEmail());
        body.put("sent", sent);
        body.put("skipped", skipped);
        body.put("results", results);
        if (sent == 0 && skipped > 0) {
            body.put("message", "No push token registered for this account. "
                    + "Open the Detrack app on your phone and sign in with " + user.getEmail() + ".");
            return Response.status(Response.Status.CONFLICT).entity(body).build();
        }
        return Response.status(207).entity(body).build();
    }

    private static Response skippedResponse(User user, String message) {
        Map<String, Object> body = new HashMap<>();
        body.put("skipped", true);
        body.put("userId", user.getId());
        body.put("email", user.getEmail());
        body.put("message", message);
        return Response.status(Response.Status.CONFLICT).entity(body).build();
    }

    private static Map<String, Object> skippedUserEntry(User user, String message) {
        Map<String, Object> entry = new HashMap<>();
        entry.put("userId", user.getId());
        entry.put("email", user.getEmail());
        entry.put("message", message);
        return entry;
    }

}
