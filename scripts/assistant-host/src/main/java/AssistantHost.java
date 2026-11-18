// SPDX-FileCopyrightText: 2026 SW9-project contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import com.google.ai.edge.litertlm.*;
import com.google.gson.*;
import com.sun.net.httpserver.*;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.security.DigestInputStream;
import java.util.*;
import java.util.concurrent.Executors;

/** Development only: real FunctionGemma inference on the emulator's host. */
public final class AssistantHost {
    private static final Gson JSON = new Gson();
    private static final int MAX_BODY = 65536;

    public static void main(String[] args) throws Exception {
        if (args.length != 1 || !Files.isRegularFile(Path.of(args[0]))) {
            throw new IllegalArgumentException("Pass the absolute path to the .litertlm model");
        }
        Path modelPath = Path.of(args[0]);
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (var input = new DigestInputStream(Files.newInputStream(modelPath), digest)) {
            input.transferTo(java.io.OutputStream.nullOutputStream());
        }
        JsonObject health = new JsonObject();
        health.addProperty("ready", true);
        health.addProperty("model", modelPath.getFileName().toString().replaceFirst("\\.litertlm$", ""));
        health.addProperty("sha256", HexFormat.of().formatHex(digest.digest()));
        Engine engine = new Engine(new EngineConfig(
            args[0], new Backend.CPU(2, null), null, null, 4096, null,
            Path.of(args[0]).getParent().toString()));
        engine.initialize();
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 8787), 4);
        // One request at a time: bound memory and never share conversation history.
        server.setExecutor(Executors.newSingleThreadExecutor());
        server.createContext("/health", exchange -> respond(exchange, 200, health.toString()));
        server.createContext("/propose", exchange -> {
            if (!exchange.getRequestMethod().equals("POST")) {
                respond(exchange, 405, "{\"error\":\"POST required\"}");
                return;
            }
            try {
                byte[] bytes = exchange.getRequestBody().readNBytes(MAX_BODY + 1);
                if (bytes.length > MAX_BODY) {
                    respond(exchange, 413, "{\"error\":\"Request too large\"}");
                    return;
                }
                JsonObject request = JsonParser.parseString(new String(bytes, StandardCharsets.UTF_8)).getAsJsonObject();
                String text = request.get("text").getAsString();
                JsonArray functions = request.getAsJsonArray("functions");
                if (text.isBlank() || text.length() > 4000 || functions.size() > 40) {
                    respond(exchange, 400, "{\"error\":\"Invalid request\"}");
                    return;
                }
                List<ToolProvider> tools = new ArrayList<>();
                for (JsonElement function : functions) {
                    tools.add(ToolKt.tool(new OpenApiTool() {
                        public String getToolDescriptionJsonString() { return function.toString(); }
                        public String execute(String ignored) { throw new IllegalStateException("Proposals only"); }
                    }));
                }
                ConversationConfig config = new ConversationConfig(
                    null, List.of(), tools, new SamplerConfig(1, 1.0, 0.0, 0), false,
                    null, Map.of(), null, false, 128);
                long started = System.nanoTime();
                try (Conversation conversation = engine.createConversation(config)) {
                    Message message = conversation.sendMessage(text);
                    JsonObject response = new JsonObject();
                    response.addProperty("total_ms", (System.nanoTime() - started) / 1_000_000);
                    if (message.getToolCalls().isEmpty()) {
                        response.add("call", JsonNull.INSTANCE);
                    } else {
                        ToolCall call = message.getToolCalls().get(0);
                        JsonObject proposal = new JsonObject();
                        proposal.addProperty("name", call.getName());
                        proposal.add("args", JSON.toJsonTree(call.getArguments()));
                        response.add("call", proposal);
                    }
                    respond(exchange, 200, response.toString());
                }
            } catch (Exception error) {
                // Never log prompts, arguments, or model responses.
                System.err.println("Inference failed: " + error.getClass().getSimpleName());
                respond(exchange, 500, "{\"error\":\"Inference failed\"}");
            }
        });
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            server.stop(0);
            engine.close();
        }));
        server.start();
        System.out.println("SW9 assistant ready at http://127.0.0.1:8787 (" + health.get("model").getAsString() + "; CPU)");
    }

    private static void respond(HttpExchange exchange, int code, String json) throws java.io.IOException {
        byte[] data = json.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
        exchange.sendResponseHeaders(code, data.length);
        try (var output = exchange.getResponseBody()) { output.write(data); }
        exchange.close();
    }
}
