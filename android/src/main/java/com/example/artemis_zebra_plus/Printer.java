package com.example.artemis_zebra_plus;

import android.Manifest;
import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.bluetooth.BluetoothDevice;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ColorMatrix;
import android.graphics.ColorMatrixColorFilter;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.location.LocationManager;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Base64;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;

import com.squareup.moshi.JsonAdapter;
import com.squareup.moshi.Moshi;
import com.zebra.sdk.comm.BluetoothConnection;
import com.zebra.sdk.comm.Connection;
import com.zebra.sdk.comm.ConnectionException;
import com.zebra.sdk.comm.TcpConnection;
import com.zebra.sdk.printer.PrinterStatus;
import com.zebra.sdk.printer.SGD;
import com.zebra.sdk.printer.ZebraPrinter;
import com.zebra.sdk.printer.ZebraPrinterFactory;
import com.zebra.sdk.printer.ZebraPrinterLanguageUnknownException;
import com.zebra.sdk.printer.discovery.BluetoothDiscoverer;
import com.zebra.sdk.printer.discovery.DiscoveredPrinter;
import com.zebra.sdk.printer.discovery.DiscoveryHandler;
import com.zebra.sdk.printer.discovery.NetworkDiscoverer;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;
import pub.devrel.easypermissions.EasyPermissions;

public class Printer extends Service implements MethodChannel.MethodCallHandler {
    private static final int ACCESS_COARSE_LOCATION_REQUEST_CODE = 100021;
    private static final int ON_DISCOVERY_ERROR_GENERAL = -1;
    private static final int ON_DISCOVERY_ERROR_BLUETOOTH = -2;
    private static final int ON_DISCOVERY_ERROR_LOCATION = -3;
    private Connection printerConnection;
    private ZebraPrinter printer;
    private Context context;
    private ActivityPluginBinding binding;
    private MethodChannel methodChannel;
    private String selectedAddress = null;
    private String macAddress = null;
    private boolean tempIsPrinterConnect;
    private static ArrayList<DiscoveredPrinter> discoveredPrinters = new ArrayList<>();
    private static ArrayList<DiscoveredPrinter> sendedDiscoveredPrinters = new ArrayList<>();
    private static int countDiscovery = 0;
    private static int countEndScan = 0;
    private boolean isZebraPrinter = true;
    private Socketmanager socketmanager;

    // Guards linkGeneration so a late ACL or poll cannot kill the next session.
    private final Object linkLock = new Object();
    private int linkGeneration = 0;
    private boolean unexpectedLossEmitted = false;
    private BroadcastReceiver aclDisconnectReceiver;
    private boolean aclReceiverRegistered = false;
    private int registeredAclGeneration = -1;

    public Printer() {
        // Default constructor is required for the Android service to work correctly
    }

    public Printer(ActivityPluginBinding binding, BinaryMessenger binaryMessenger) {
        this.context = binding.getActivity();
        this.binding = binding;
        this.methodChannel = new MethodChannel(binaryMessenger, "ZebraPrinterInstance" + this.toString());
        methodChannel.setMethodCallHandler(this);

    }

    private static final Moshi moshi = new Moshi.Builder().build();

    @Override
    public void onMethodCall(@NonNull final MethodCall call, @NonNull final MethodChannel.Result result) {

        switch (call.method) {
            case "checkPermissions":
                checkPermissions(result);
                break;

            case "discoverPrinters":
                discoverPrinters(context, result);
                break;

            case "connectToPrinter":
                String address = Objects.requireNonNull(call.argument("address")).toString();
                connectToPrinter(address, result);
                break;

            case "printData":
                String data = Objects.requireNonNull(call.argument("data")).toString();
                printData(data, result);
                break;

            case "disconnectPrinter":
                disconnectPrinter(result);
                break;

            case "isPrinterConnected":
                isPrinterConnect(result);
                break;


            case "checkPrinterStatus":
                Boolean sgdOnlyArg = call.argument("sgdOnly");
                checkPrinterStatus(result, Boolean.TRUE.equals(sgdOnlyArg));
                break;

            default:
                result.notImplemented();
        }

    }

    public void callHandlers(@NonNull final String method, @Nullable Object arguments) {
        new Handler(Looper.getMainLooper()).post(new Runnable() {
            @Override
            public void run() {
                methodChannel.invokeMethod(method, arguments);
            }
        });
    }

    public void discoverPrinters(final Context context, final MethodChannel.Result result) {
        try {

            BluetoothDiscoverer.findPrinters(this.context, new DiscoveryHandler() {
                @Override
                public void foundPrinter(final DiscoveredPrinter discoveredPrinter) {
                    ((Activity) context).runOnUiThread(() -> {

                        String address = discoveredPrinter.address;
                        Log.println(Log.ASSERT, "Printer Found!!!", "Printer Found " + discoveredPrinter.address);

                        String name = discoveredPrinter.getDiscoveryDataMap().get("FRIENDLY_NAME");
                        HashMap<String, Object> arguments = new HashMap<>();
                        arguments.put("address", address);
                        arguments.put("name", name);
                        arguments.put("type", 1);
                        arguments.put("isConnected", discoveredPrinter.getConnection().isConnected());
                        JsonAdapter<Map> adapter = moshi.adapter(Map.class);
                        methodChannel.invokeMethod("printerFound", adapter.toJson(arguments));
//                        methodChannel.invokeMethod("printerFound", new Gson().toJson(arguments));
                    });
                }

                @Override
                public void discoveryFinished() {
                    countEndScan++;
                    Log.println(Log.ASSERT, "Bluetooth Discovery", "Discovery Finish");
                    if (countEndScan == 2) {
                        countEndScan = 0;
                        try {
                            result.success("DiscoveryDone");
                        } catch (Exception e) {
                            e.printStackTrace();
                            Log.println(Log.ASSERT, "P", e.toString());
                        }
                    }
                }

                @Override
                public void discoveryError(String s) {
                    HashMap<String, Object> arguments = new HashMap<>();
                    arguments.put("error", s);
                    methodChannel.invokeMethod("discoveryError", arguments);
                }
            });


//            BluetoothDiscoverer.findPrinters(context, new DiscoveryHandler() {
//                @Override
//                public void foundPrinter(final DiscoveredPrinter discoveredPrinter) {
////                    discoveredPrinters.add(discoveredPrinter);
//                    ((Activity) context).runOnUiThread(new Runnable() {
//                        @Override
//                        public void run() {
//                            Log.println(Log.ASSERT,"Printer Found!!!","Printer Found");
//                            HashMap<String, Object> arguments = new HashMap<>();
//                            arguments.put("address", discoveredPrinter.address);
//                            arguments.put("name", discoveredPrinter.getDiscoveryDataMap().get("FRIENDLY_NAME"));
//                            arguments.put("type", 1);
//                            methodChannel.invokeMethod("printerFound", new Gson().toJson(arguments));
//                        }
//                    });
//                }
//
//                @Override
//                public void discoveryFinished() {
//                    result.success("DiscoveryDone");
//                }
//
//                @Override
//                public void discoveryError(String s) {
//                    Log.println(Log.ASSERT,"P","FindPrintersError!!!!!"+s);
//
//                    HashMap<String, Object> arguments = new HashMap<>();
//                    arguments.put("error", s);
//                    methodChannel.invokeMethod("discoveryError", arguments);
//                }
//            });

//            BluetoothDiscoverer.findPrinters();
            NetworkDiscoverer.findPrinters(new DiscoveryHandler() {
                @Override
                public void foundPrinter(DiscoveredPrinter discoveredPrinter) {
                    ((Activity) context).runOnUiThread(() -> {
                        HashMap<String, Object> arguments = new HashMap<>();
                        arguments.put("address", discoveredPrinter.address);
                        arguments.put("name", discoveredPrinter.getDiscoveryDataMap().get("SYSTEM_NAME"));
                        arguments.put("type", 0);
                        arguments.put("isConnected", discoveredPrinter.getConnection().isConnected());
//                        arguments.put("isConnected", discoveredPrinter);
                        JsonAdapter<Map> adapter = moshi.adapter(Map.class);
                        methodChannel.invokeMethod("printerFound", adapter.toJson(arguments));
//                        methodChannel.invokeMethod("printerFound", new Gson().toJson(arguments));
                    });
                }

                @Override
                public void discoveryFinished() {
                    countEndScan++;
                    Log.println(Log.ASSERT, "Network Discovery", "Discovery Finish");
                    if (countEndScan == 2) {
                        try {
                            try {
                                result.success("DiscoveryDone");

                            } catch (Exception e) {

                            }
                        } catch (Exception e) {
                            e.printStackTrace();
                            Log.println(Log.ASSERT, "P", e.toString());
                        }
                    }
//
                }

                @Override
                public void discoveryError(String s) {
                    HashMap<String, Object> arguments = new HashMap<>();
                    arguments.put("error", s);
                    methodChannel.invokeMethod("discoveryError", arguments);
                }
            });
        } catch (Exception e) {
            e.printStackTrace();
            Log.println(Log.ASSERT, "P", e.toString());

        }
    }

    public void connectToPrinter(final String address, final MethodChannel.Result result) {
        // Drop the previous socket's listener before opening a new one.
        retireCurrentLink();
        final int generation;
        synchronized (linkLock) {
            generation = linkGeneration;
        }
        if (address.contains(":")) {
            printerConnection = new BluetoothConnection(address);
        } else {
            try {
                printerConnection = new TcpConnection(address, getTcpPortNumber());
            } catch (NumberFormatException e) {
                result.error("1", e.toString(), e);
            }
        }

        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    printerConnection.open();
                } catch (ConnectionException e) {
                    DemoSleeper.sleep(1000);
                    disconnectPrinter(null);
                    result.success(false);
                }
                if (printerConnection.isConnected()) {
                    try {
                        printer = ZebraPrinterFactory.getInstance(printerConnection);
                        startService(address);
                        if (printerConnection instanceof BluetoothConnection) {
                            String mac = ((BluetoothConnection) printerConnection).getMACAddress();
                            if (mac == null || mac.isEmpty()) {
                                mac = address;
                            }
                            registerAclDisconnectListener(mac, generation);
                        }
                        try {
                            result.success(true);
                        } catch (Exception e) {

                        }

                    } catch (ConnectionException e) {
                        printer = null;
                        DemoSleeper.sleep(1000);
                        disconnectPrinter(null);
                        stopService();
                        try {
                            result.success(false);
                        } catch (Exception e2) {

                        }
                    } catch (ZebraPrinterLanguageUnknownException e) {
                        printer = null;
                        DemoSleeper.sleep(1000);
                        disconnectPrinter(null);
                        stopService();
                        try {
                            result.success(false);
                        } catch (Exception e2) {

                        }

                    }
                }
            }
        }).start();

    }

    private void startService(final String address) {
//        Intent serviceIntent = new Intent(context, Printer.class);
//        serviceIntent.putExtra("printer_address", address);
//        context.startService(serviceIntent);
    }

    private void stopService() {
//        Intent serviceIntent = new Intent(context, Printer.class);
//        context.stopService(serviceIntent);
    }

    private void printData(String data, final MethodChannel.Result result) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    byte[] bytes = convertDataToByte(data);
                    printerConnection.write(bytes);
                    DemoSleeper.sleep(1500);

                    if (printerConnection instanceof BluetoothConnection) {
                        DemoSleeper.sleep(500);
                    }
                    result.success(true);
                } catch (ConnectionException e) {
                    result.error("1", e.toString(), e);
                    disconnectPrinter(null);
                }
            }
        }).start();


    }

    public void disconnectPrinter(final MethodChannel.Result result) {
        // Bump the generation before close so this socket's ACL drop is not a second loss event.
        retireCurrentLink();
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    if (isZebraPrinter) {
                        try {
                            if (printerConnection != null) {
                                printerConnection.close();
                            }

                            callHandlers("connectionLost", null);
                        } catch (ConnectionException e) {
                            e.printStackTrace();
                            callHandlers("connectionLost", null);

                        } finally {
                            if (result != null) {
                                stopService();
                                new Handler(Looper.getMainLooper()).post(new Runnable() {
                                    @Override
                                    public void run() {
                                        result.success(true);
                                    }
                                });
                            }
                            callHandlers("connectionLost", null);

                        }
                    } else {
                        socketmanager.close();
                        if (result != null) {
                            stopService();
                            new Handler(Looper.getMainLooper()).post(new Runnable() {
                                @Override
                                public void run() {
                                    result.success(true);
                                }
                            });
                        }
                        new Handler(Looper.getMainLooper()).post(new Runnable() {
                            @Override
                            public void run() {
                                methodChannel.invokeMethod("connectionLost", null);
                            }
                        });
                    }
                } catch (Exception e) {
                    DemoSleeper.sleep(1000);
                    try {
                        new Handler(Looper.getMainLooper()).post(new Runnable() {
                            @Override
                            public void run() {
                                result.success(true);
                            }
                        });
                    } catch (Exception ee) {
                        // Handle nested exception if needed
                    }
                    callHandlers("connectionLost", null);

                }
            }
        }).start();


//        new Handler(Looper.getMainLooper()).post(() -> { result.success(lists); });
//
//
//
//
//        new Thread(new Runnable() {
//            @Override
//            public void run() {
//                try {
//                    if (isZebraPrinter) {
//                        try {
//                            if (printerConnection != null) {
//                                printerConnection.close();
//                            }
//                            methodChannel.invokeMethod("connectionLost", null);
//
//                        } catch (ConnectionException e) {
//                            e.printStackTrace();
//                            methodChannel.invokeMethod("connectionLost", null);
//
//                        } finally {
//                            if (result != null) {
//                                stopService();
//                                result.success(true);
//                            }
//                            methodChannel.invokeMethod("connectionLost", null);
//
//                        }
//                    } else {
//                        socketmanager.close();
//                        if (result != null) {
//                            stopService();
//                            result.success(true);
//                        }
//                        methodChannel.invokeMethod("connectionLost", null);
//
//                    }
//                } catch (Exception e) {
//                    DemoSleeper.sleep(1000);
//                    try {
//                        result.success(true);
//                    }catch (Exception ee){
//
//                    }
//                    methodChannel.invokeMethod("connectionLost", null);
//
//                }
//
//            }
//        }).start();


    }

    public void isPrinterConnect(final MethodChannel.Result result) {
        if (isZebraPrinter) {
            tempIsPrinterConnect = true;
            if (printerConnection != null && printerConnection.isConnected()) {
                new Thread(new Runnable() {
                    public void run() {
                        try {
                            printerConnection.write("Test".getBytes());
                        } catch (ConnectionException e) {
                            e.printStackTrace();
                            disconnectPrinter(null);
                            tempIsPrinterConnect = false;
                        }
                    }
                }).start();
                if (tempIsPrinterConnect) {
                    result.success(true);
                } else {
                    result.success(false);
                }
            } else {
                result.success(false);
            }
        } else {
            if (socketmanager != null) {
                if (socketmanager.getIstate()) {
                    result.success(true);
                } else {
                    result.success(false);
                }
            } else {
                result.success(false);
            }
        }
    }

    /**
     * Link-OS battery via SGD on the open connection. Returns null when the
     * printer is AC-powered, SGD is missing, or the value cannot be parsed.
     * Never uses 0 as a stand-in for "unknown".
     */
    private Integer readBatteryPercent(Connection connection) throws ConnectionException {
        try {
            String source = SGD.GET("power.source", connection);
            android.util.Log.d("BatterySgd", "power.source raw='" + source + "'");
            // Missing / garbage source must not block charge reads — only skip on clear AC/line/mains.
            if (looksLikeValidSgdScalar(source) && isAcPowerSource(source)) {
                android.util.Log.d("BatterySgd", "skipping percent — AC/line/mains source '" + source + "'");
                return null;
            }
            String[] keys = new String[]{
                    "power.percent_full",
                    "power.relative_state_of_charge",
                    "power.percent",
                    "power.percentage",
            };
            Integer parsed = null;
            for (String key : keys) {
                String raw = SGD.GET(key, connection);
                android.util.Log.d("BatterySgd", key + " raw='" + raw + "'");
                parsed = parseBatteryPercent(raw);
                if (parsed != null) {
                    break;
                }
            }
            android.util.Log.d("BatterySgd", "parsed batteryPercent=" + parsed);
            return parsed;
        } catch (ConnectionException e) {
            // Power-off and out-of-range throw here. isConnected() stays true until close().
            android.util.Log.w("BatterySgd", "readBatteryPercent link failed", e);
            throw e;
        } catch (Exception e) {
            android.util.Log.w("BatterySgd", "readBatteryPercent failed", e);
            return null;
        }
    }

    private static boolean isAcPowerSource(String source) {
        if (source == null) {
            return false;
        }
        String src = source.trim().toUpperCase();
        if (src.isEmpty()) {
            return false;
        }
        // Prefer exact / prefix matches — avoid bare contains("AC") false positives.
        if (src.equals("AC") || src.equals("LINE") || src.equals("MAINS")) {
            return true;
        }
        return src.startsWith("AC") || src.contains("LINE") || src.contains("MAINS");
    }

    /**
     * Rejects leftover host-status blobs that are not valid power.* scalars.
     */
    static boolean looksLikeValidSgdScalar(String raw) {
        if (raw == null) {
            return false;
        }
        String s = raw.trim();
        if (s.isEmpty() || s.length() > 64) {
            return false;
        }
        if (s.contains("^B") || s.contains("^C")) {
            return false;
        }
        if (s.indexOf((char) 0x02) >= 0 || s.indexOf((char) 0x03) >= 0) {
            return false;
        }
        return s.indexOf('\n') < 0;
    }

    /**
     * Parses a leading 0–100 integer from SGD strings like "91", "91%", "91% Full".
     */
    static Integer parseBatteryPercent(String raw) {
        if (!looksLikeValidSgdScalar(raw)) {
            return null;
        }
        String s = raw.trim();
        int start = -1;
        int end = s.length();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c >= '0' && c <= '9') {
                if (start < 0) {
                    start = i;
                }
            } else if (start >= 0) {
                end = i;
                break;
            }
        }
        if (start < 0) {
            return null;
        }
        try {
            int n = Integer.parseInt(s.substring(start, end));
            if (n < 0 || n > 100) {
                return null;
            }
            return n;
        } catch (NumberFormatException e) {
            return null;
        }
    }

    /**
     * Invalidates the current link so a late ACL broadcast or poll from this
     * socket cannot mark a newer session disconnected.
     */
    private void retireCurrentLink() {
        synchronized (linkLock) {
            linkGeneration++;
            unexpectedLossEmitted = false;
        }
        unregisterAclDisconnectListener();
    }

    /**
     * BluetoothSocket.isConnected() stays true after the printer powers off
     * until close(). ACL_DISCONNECTED is the OS signal for that drop.
     */
    private void registerAclDisconnectListener(final String mac, final int generation) {
        if (context == null || mac == null || mac.isEmpty()) {
            return;
        }
        unregisterAclDisconnectListener();
        aclDisconnectReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context ctx, Intent intent) {
                if (intent == null || !BluetoothDevice.ACTION_ACL_DISCONNECTED.equals(intent.getAction())) {
                    return;
                }
                final Connection dying;
                synchronized (linkLock) {
                    if (generation != linkGeneration) {
                        return;
                    }
                    dying = printerConnection;
                }
                BluetoothDevice device;
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice.class);
                } else {
                    device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
                }
                if (device == null || device.getAddress() == null) {
                    return;
                }
                if (!mac.equalsIgnoreCase(device.getAddress())) {
                    return;
                }
                android.util.Log.d("BatterySgd", "ACL disconnected mac=" + device.getAddress());
                reportUnexpectedLinkLoss(null, dying, generation);
            }
        };
        IntentFilter filter = new IntentFilter(BluetoothDevice.ACTION_ACL_DISCONNECTED);
        Context appContext = context.getApplicationContext();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(aclDisconnectReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            appContext.registerReceiver(aclDisconnectReceiver, filter);
        }
        aclReceiverRegistered = true;
        registeredAclGeneration = generation;
    }

    private void unregisterAclDisconnectListener() {
        if (!aclReceiverRegistered || aclDisconnectReceiver == null || context == null) {
            aclReceiverRegistered = false;
            aclDisconnectReceiver = null;
            registeredAclGeneration = -1;
            return;
        }
        try {
            context.getApplicationContext().unregisterReceiver(aclDisconnectReceiver);
        } catch (IllegalArgumentException ignored) {
            // Already unregistered — safe when connect and disconnect overlap.
        }
        aclReceiverRegistered = false;
        aclDisconnectReceiver = null;
        registeredAclGeneration = -1;
    }

    /**
     * Closes [dying] and tells Dart the link is gone, once per generation.
     * Completes [result] with "Not Connected" even when a newer session owns the radio.
     */
    private void reportUnexpectedLinkLoss(
            @Nullable final MethodChannel.Result result,
            @Nullable final Connection dying,
            final int generation
    ) {
        final boolean emit;
        synchronized (linkLock) {
            if (generation == linkGeneration && !unexpectedLossEmitted) {
                unexpectedLossEmitted = true;
                emit = true;
            } else {
                emit = false;
            }
        }
        if (registeredAclGeneration == generation) {
            unregisterAclDisconnectListener();
        }
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    if (dying != null) {
                        dying.close();
                    }
                } catch (Exception ignored) {
                    // Already closed, or the printer dropped mid-close.
                }
                synchronized (linkLock) {
                    if (printerConnection == dying) {
                        printerConnection = null;
                        printer = null;
                    }
                }
                // A connect that started after this drop owns the session now.
                final boolean emitNow;
                synchronized (linkLock) {
                    emitNow = emit && generation == linkGeneration;
                }
                if (emitNow) {
                    callHandlers("connectionLost", null);
                }
                if (result != null) {
                    try {
                        result.success("Not Connected");
                    } catch (Exception ignored) {
                        // Result was already completed by a racing loss path.
                    }
                }
            }
        }).start();
    }

    public void checkPrinterStatus(final MethodChannel.Result result) {
        checkPrinterStatus(result, false);
    }

    public void checkPrinterStatus(final MethodChannel.Result result, final boolean sgdOnly) {
        tempIsPrinterConnect = true;
        final int generation;
        final Connection connection;
        synchronized (linkLock) {
            generation = linkGeneration;
        }
        connection = printerConnection;
        // sgdOnly polls must not reopen a dead socket — that hides power-off.
        if (connection == null || !connection.isConnected()) {
            reportUnexpectedLinkLoss(result, connection, generation);
            return;
        }
        new Thread(new Runnable() {
            public void run() {
                if (!sgdOnly) {
                    try {
                        connection.open();
                    } catch (ConnectionException e) {
                        reportUnexpectedLinkLoss(result, connection, generation);
                        return;
                    }
                } else {
                    // Short read so a powered-off printer fails the poll in ~2s, not the SDK default.
                    connection.setMaxTimeoutForRead(2000);
                    connection.setTimeToWaitForMoreData(200);
                }
                if (!connection.isConnected()) {
                    reportUnexpectedLinkLoss(result, connection, generation);
                    return;
                }

                HashMap<String, Object> arguments = new HashMap<>();
                // Defaults when getCurrentStatus fails (malformed status blob).
                arguments.put("isHeadCold", false);
                arguments.put("isReadyToPrint", true);
                arguments.put("isHeadOpen", false);
                arguments.put("isPaperOut", false);
                arguments.put("isHeadTooHot", false);
                arguments.put("isPartialFormatInProgress", false);
                arguments.put("isPaused", false);
                arguments.put("isReceiveBufferFull", false);
                arguments.put("isRibbonOut", false);
                arguments.put("labelLengthInDots", 0);
                arguments.put("numberOfFormatsInReceiveBuffer", 0);
                arguments.put("printMode", 0);
                arguments.put("labelsRemainingInBatch", 0);

                // Periodic battery polls skip getCurrentStatus — it is slow and often malformed.
                if (!sgdOnly) {
                    try {
                        ZebraPrinter printer = ZebraPrinterFactory.getInstance(connection);
                        PrinterStatus printerStatus = printer.getCurrentStatus();
                        MyPrinterStatus myPrinterStatus = new MyPrinterStatus(
                                printerStatus.isReadyToPrint,
                                printerStatus.isHeadOpen,
                                printerStatus.isHeadCold,
                                printerStatus.isHeadTooHot,
                                printerStatus.isPaperOut,
                                printerStatus.isRibbonOut,
                                printerStatus.isReceiveBufferFull,
                                printerStatus.isPaused,
                                printerStatus.labelLengthInDots,
                                printerStatus.numberOfFormatsInReceiveBuffer,
                                printerStatus.labelsRemainingInBatch,
                                printerStatus.isPartialFormatInProgress,
                                printerStatus.printMode.ordinal());
                        arguments.put("isHeadCold", myPrinterStatus.isHeadCold);
                        arguments.put("isReadyToPrint", myPrinterStatus.isReadyToPrint);
                        arguments.put("isHeadOpen", myPrinterStatus.isHeadOpen);
                        arguments.put("isPaperOut", myPrinterStatus.isPaperOut);
                        arguments.put("isHeadTooHot", myPrinterStatus.isHeadTooHot);
                        arguments.put("isPartialFormatInProgress", myPrinterStatus.isPartialFormatInProgress);
                        arguments.put("isPaused", myPrinterStatus.isPaused);
                        arguments.put("isReceiveBufferFull", myPrinterStatus.isReceiveBufferFull);
                        arguments.put("isRibbonOut", myPrinterStatus.isRibbonOut);
                        arguments.put("labelLengthInDots", myPrinterStatus.labelLengthInDots);
                        arguments.put("numberOfFormatsInReceiveBuffer", myPrinterStatus.numberOfFormatsInReceiveBuffer);
                        arguments.put("printMode", myPrinterStatus.printMode);
                        arguments.put("labelsRemainingInBatch", myPrinterStatus.labelsRemainingInBatch);
                    } catch (Exception e) {
                        // Malformed status / language unknown — still read SGD battery below.
                        android.util.Log.w("BatterySgd",
                                "getCurrentStatus failed: " + e.getMessage() + " — reading SGD battery anyway");
                    }
                }

                final Integer batteryPercent;
                try {
                    batteryPercent = readBatteryPercent(connection);
                } catch (ConnectionException e) {
                    reportUnexpectedLinkLoss(result, connection, generation);
                    return;
                }
                if (batteryPercent != null) {
                    arguments.put("batteryPercent", batteryPercent);
                }
                android.util.Log.d("BatterySgd", "checkPrinterStatus sgdOnly=" + sgdOnly
                        + " batteryPercent=" + batteryPercent);

                JsonAdapter<Map> adapter = moshi.adapter(Map.class);
                try {
                    result.success(adapter.toJson(arguments));
                } catch (Exception ignored) {
                    // Result was already completed.
                }
            }
        }).start();
    }


    private void checkPermissions(final MethodChannel.Result result) {
        List<String> listPermissionsNeeded = new ArrayList<>();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (context.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
                listPermissionsNeeded.add(Manifest.permission.BLUETOOTH_SCAN);
            }
            if (context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                listPermissionsNeeded.add(Manifest.permission.BLUETOOTH_CONNECT);
            }
            if (context.checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) != PackageManager.PERMISSION_GRANTED) {
                listPermissionsNeeded.add(Manifest.permission.BLUETOOTH_ADVERTISE);
            }
            if (context.checkSelfPermission(Manifest.permission.BLUETOOTH_PRIVILEGED) != PackageManager.PERMISSION_GRANTED) {
                listPermissionsNeeded.add(Manifest.permission.BLUETOOTH_PRIVILEGED);
            }
            if (context.checkSelfPermission(Manifest.permission.FOREGROUND_SERVICE) != PackageManager.PERMISSION_GRANTED) {
                listPermissionsNeeded.add(Manifest.permission.FOREGROUND_SERVICE);
            }
            if (context.checkSelfPermission(Manifest.permission.BLUETOOTH) != PackageManager.PERMISSION_GRANTED) {
                listPermissionsNeeded.add(Manifest.permission.BLUETOOTH);
            }
            if (context.checkSelfPermission(Manifest.permission.BLUETOOTH_ADMIN) != PackageManager.PERMISSION_GRANTED) {
                listPermissionsNeeded.add(Manifest.permission.BLUETOOTH_ADMIN);
            }
            if (!listPermissionsNeeded.isEmpty()) {
                binding.addRequestPermissionsResultListener(new PluginRegistry.RequestPermissionsResultListener() {
                    @Override
                    public boolean onRequestPermissionsResult(int requestCode, String[] listPermissionsNeeded, int[] grantResults) {
//                        if (requestCode == ACCESS_COARSE_LOCATION_REQUEST_CODE) {
                        if (grantResults.length > 0) if (grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                            try {
                                result.success(true);
                                return true;
                            } catch (Exception e) {
                                result.success(false);
                                return false;
                            }
                        }
//                        }
                        try {
                            result.success(false);
                            return false;
                        } catch (Exception e) {
                            result.success(false);
                            return false;
                        }
                    }
                });
                ((Activity) context).requestPermissions(listPermissionsNeeded.toArray(new String[0]), ACCESS_COARSE_LOCATION_REQUEST_CODE);
            } else {
                result.success(true);
            }

        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                listPermissionsNeeded.add(Manifest.permission.ACCESS_COARSE_LOCATION);
            }
            if (context.checkSelfPermission(Manifest.permission.BLUETOOTH) != PackageManager.PERMISSION_GRANTED) {
                listPermissionsNeeded.add(Manifest.permission.BLUETOOTH);
            }
//            if (context.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
//                listPermissionsNeeded.add(Manifest.permission.BLUETOOTH_SCAN);
//            }
            if (context.checkSelfPermission(Manifest.permission.BLUETOOTH_PRIVILEGED) != PackageManager.PERMISSION_GRANTED) {
                listPermissionsNeeded.add(Manifest.permission.BLUETOOTH_PRIVILEGED);
            }
            if (context.checkSelfPermission(Manifest.permission.FOREGROUND_SERVICE) != PackageManager.PERMISSION_GRANTED) {
                listPermissionsNeeded.add(Manifest.permission.FOREGROUND_SERVICE);
            }
//            if (context.checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) != PackageManager.PERMISSION_GRANTED) {
//                listPermissionsNeeded.add(Manifest.permission.BLUETOOTH_ADVERTISE);
//            }

            if (!listPermissionsNeeded.isEmpty()) {
                binding.addRequestPermissionsResultListener(new PluginRegistry.RequestPermissionsResultListener() {
                    @Override
                    public boolean onRequestPermissionsResult(int requestCode, String[] listPermissionsNeeded, int[] grantResults) {
//                        if (requestCode == ACCESS_COARSE_LOCATION_REQUEST_CODE) {
                        if (grantResults.length > 0) if (grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                            try {
                                result.success(true);
                                return true;
                            } catch (Exception e) {
                                result.success(false);
                                return false;
                            }
                        }
//                        }
                        try {
                            result.success(false);
                            return false;
                        } catch (Exception e) {
                            result.success(false);
                            return false;
                        }
                    }
                });
                ((Activity) context).requestPermissions(listPermissionsNeeded.toArray(new String[0]), ACCESS_COARSE_LOCATION_REQUEST_CODE);
            } else {
                result.success(true);
            }
        }
//
//        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
//
//        }


    }


//    public ZebraPrinter connect(boolean isBluetoothPrinter) {
//
//
//        printerConnection = null;
//        if (isBluetoothPrinter) {
//
//        } else {
//            try {
//
//
//            }
//        }
//        try {
//            printerConnection.open();
//
//        } catch (ConnectionException e) {
//            DemoSleeper.sleep(1000);
//            disconnect();
//            return null;
//        }
//
//        ZebraPrinter printer = null;
//
//        if (printerConnection.isConnected()) {
//            try {
//                printer = ZebraPrinterFactory.getInstance(printerConnection);
//            } catch (ConnectionException e) {
//                printer = null;
//                DemoSleeper.sleep(1000);
//                disconnect();
//            } catch (ZebraPrinterLanguageUnknownException e) {
//                printer = null;
//                DemoSleeper.sleep(1000);
//                disconnect();
//            }
//        }
//        setStatus(context.getString(R.string.connected), context.getString(R.string.connectedColor));
//        return printer;
//    }


//    public static void discoveryPrinters(final Context context, final MethodChannel methodChannel) {
//
//        try {
//            sendedDiscoveredPrinters.clear();
//            for (DiscoveredPrinter dp :
//                    discoveredPrinters) {
//                addNewDiscoverPrinter(dp, context, methodChannel);
//            }
//            countEndScan = 0;
//            BluetoothDiscoverer.findPrinters(context, new DiscoveryHandler() {
//                @Override
//                public void foundPrinter(final DiscoveredPrinter discoveredPrinter) {
//                    discoveredPrinters.add(discoveredPrinter);
//                    ((Activity) context).runOnUiThread(new Runnable() {
//                        @Override
//                        public void run() {
//                            addNewDiscoverPrinter(discoveredPrinter, context, methodChannel);
//                        }
//                    });
//                }
//
//                @Override
//                public void discoveryFinished() {
//                    countEndScan++;
//                    finishScanPrinter(context, methodChannel);
//                }
//
//                @Override
//                public void discoveryError(String s) {
//                    if(s.contains("Bluetooth radio is currently disabled"))
//                        onDiscoveryError(context, methodChannel, ON_DISCOVERY_ERROR_BLUETOOTH, s);
//                    else
//                        onDiscoveryError(context, methodChannel, ON_DISCOVERY_ERROR_GENERAL, s);
//                    countEndScan++;
//                    finishScanPrinter(context, methodChannel);
//                }
//            });
//
//
//            NetworkDiscoverer.findPrinters(new DiscoveryHandler() {
//                @Override
//                public void foundPrinter(DiscoveredPrinter discoveredPrinter) {
//                    addNewDiscoverPrinter(discoveredPrinter, context, methodChannel);
//
//                }
//
//                @Override
//                public void discoveryFinished() {
//                    countEndScan++;
//                    finishScanPrinter(context, methodChannel);
//                }
//
//                @Override
//                public void discoveryError(String s) {
//                    onDiscoveryError(context, methodChannel, ON_DISCOVERY_ERROR_GENERAL, s);
//                    countEndScan++;
//                    finishScanPrinter(context, methodChannel);
//                }
//            });
//        } catch (Exception e) {
//            e.printStackTrace();
//        }
//    }

//    private static void onDiscoveryError(Context context, final MethodChannel methodChannel, final int errorCode, final String errorText) {
//        ((Activity) context).runOnUiThread(new Runnable() {
//            @Override
//            public void run() {
//                HashMap<String, Object> arguments = new HashMap<>();
//                arguments.put("ErrorCode", errorCode);
//                arguments.put("ErrorText", errorText);
//                methodChannel.invokeMethod("onDiscoveryError", arguments);
//            }
//        });
//
//    }


//    private static void addPrinterToDiscoveryPrinterList(DiscoveredPrinter discoveredPrinter) {
//        for (DiscoveredPrinter dp :
//                discoveredPrinters) {
//            if (dp.address.equals(discoveredPrinter.address))
//                return;
//        }
//
//        discoveredPrinters.add(discoveredPrinter);
//    }


//    private static void addNewDiscoverPrinter(final DiscoveredPrinter discoveredPrinter, Context context, final MethodChannel methodChannel) {
//
//        addPrinterToDiscoveryPrinterList(discoveredPrinter);
//        ((Activity) context).runOnUiThread(new Runnable() {
//            @Override
//            public void run() {
//                for (DiscoveredPrinter dp :
//                        sendedDiscoveredPrinters) {
//                    if (dp.address.equals(discoveredPrinter.address))
//                        return;
//                }
//                sendedDiscoveredPrinters.add(discoveredPrinter);
//                HashMap<String, Object> arguments = new HashMap<>();
//
//                arguments.put("Address", discoveredPrinter.address);
//                if (discoveredPrinter.getDiscoveryDataMap().get("SYSTEM_NAME") != null) {
//                    arguments.put("Name", discoveredPrinter.getDiscoveryDataMap().get("SYSTEM_NAME"));
//                    arguments.put("IsWifi", true);
//                    methodChannel.invokeMethod("printerFound"
//                            , arguments);
//                } else {
//                    arguments.put("Name", discoveredPrinter.getDiscoveryDataMap().get("FRIENDLY_NAME"));
//                    arguments.put("IsWifi", false);
//                    methodChannel.invokeMethod("printerFound"
//                            , arguments);
//                }
//            }
//        });
//    }


//    private static void finishScanPrinter(final Context context, final MethodChannel methodChannel) {
//        if (countEndScan == 2) {
//            if (discoveredPrinters.size() == 0) {
//                if (discoveryPrintersAgain(context, methodChannel))
//                    return;
//            }
//            ((Activity) context).runOnUiThread(new Runnable() {
//                @Override
//                public void run() {
//                    methodChannel.invokeMethod("onPrinterDiscoveryDone",
//                            context.getResources().getString(R.string.done));
//                }
//            });
//        }
//    }

//    private static boolean discoveryPrintersAgain(Context context, MethodChannel methodChannel) {
//        System.out.print("Discovery printers again");
//        countDiscovery++;
//        if (countDiscovery < 2) {
//            discoveryPrinters(context, methodChannel);
//            return true;
//        }
//        return false;
//    }


//    public void print(final String data) {
//        new Thread(new Runnable() {
//            public void run() {
////                enableTestButton(false);
//                Looper.prepare();
//                doConnectionTest(data);
//                Looper.loop();
//                Looper.myLooper().quit();
//            }
//        }).start();
//    }


//    private void doConnectionTest(String data) {
//
//        if (isZebraPrinter) {
//            if (printer != null) {
//                printData(data);
//            } else {
//                disconnect();
//            }
//        } else {
//            printDataGenericPrinter(data);
//        }
//    }

//    private void printDataGenericPrinter(String data) {
//        setStatus(context.getString(R.string.sending_data), context.getString(R.string.connectingColor));
//        socketmanager.threadconnectwrite(convertDataToByte(data));
//        try {
//            Thread.sleep(100);
//        } catch (InterruptedException e) {
//            e.printStackTrace();
//        }
//        if (socketmanager.getIstate()) {
//            setStatus(context.getResources().getString(R.string.done), context.getString(R.string.connectedColor));
//        } else {
//            setStatus(context.getResources().getString(R.string.disconnect), context.getString(R.string.disconnectColor));
//        }
//
//        byte sendCut[] = {0x0a, 0x0a, 0x1d, 0x56, 0x01};
//        socketmanager.threadconnectwrite(sendCut);
//        try {
//            Thread.sleep(100);
//        } catch (InterruptedException e) {
//            e.printStackTrace();
//        }
//        if (!socketmanager.getIstate()) {
//            setStatus(context.getResources().getString(R.string.disconnect)
//                    , context.getString(R.string.disconnectColor));
//        }
//    }


//    public boolean connectToSelectPrinter(String address) {
//        isZebraPrinter = true;
//        setStatus(context.getString(R.string.connecting), context.getString(R.string.connectingColor));
//        selectedAddress = null;
//        macAddress = null;
//        boolean isBluetoothPrinter;
//        if (address.contains(":")) {
//            macAddress = address;
//            isBluetoothPrinter = true;
//        } else {
//            this.selectedAddress = address;
//            isBluetoothPrinter = false;
//        }
//        printer = connect(isBluetoothPrinter);
//        if (printer != null) return true;
//        return false;
//    }


//    public void connectToGenericPrinter(String ipAddress) {
//        this.isZebraPrinter = false;
//        if (isPrinterConnect().equals(context.getString(R.string.connected))) {
//            disconnect();
//            setStatus(context.getString(R.string.connecting), context.getString(R.string.connectingColor));
//        }
//        if (socketmanager == null)
//            socketmanager = new Socketmanager(context);
//        socketmanager.mPort = getGenericPortNumber();
//        socketmanager.mstrIp = ipAddress;
//        socketmanager.threadconnect();
//        try {
//            Thread.sleep(100);
//        } catch (InterruptedException e) {
//            e.printStackTrace();
//        }
//        if (socketmanager.getIstate()) {
//            setStatus(context.getString(R.string.connected), context.getString(R.string.connectedColor));
//        } else {
//            setStatus(context.getString(R.string.disconnect), context.getString(R.string.disconnectColor));
//        }
//    }


//    private String getMacAddress() {
//        return macAddress;
//    }

//    private static String convertMacAddressToMacAddressApp(String macAddress) {
//        return macAddress;
//    }
//
//    private String getTcpAddress() {
//        return selectedAddress;
//    }


    private void setStatus(final String message, final String color) {
        ((Activity) context).runOnUiThread(new Runnable() {
            @Override
            public void run() {
                System.out.println("Printer set status: " + message);
                HashMap<String, Object> arguments = new HashMap<>();
                arguments.put("Status", message);
                arguments.put("Color", color + "");
                methodChannel.invokeMethod("changePrinterStatus", arguments);
            }
        });

    }

    private int getTcpPortNumber() {
        return 6101;
    }

    private int getGenericPortNumber() {
        return 9100;
    }

    private byte[] convertDataToByte(String data) {
        return data.getBytes();
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        // Create a notification for the foreground service
//        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
//            NotificationChannel channel = new NotificationChannel(
//                    "PrinterChannelId",
//                    "Printer Service",
//                    NotificationManager.IMPORTANCE_DEFAULT
//            );
//            NotificationManager manager = context.getApplicationContext().getSystemService(NotificationManager.class);
//            if (manager != null) {
//                manager.createNotificationChannel(channel);
//            }
//        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            createNotificationChannel();
        }


//        Intent notificationIntent = new Intent(this, Printer.class);
//        PendingIntent pendingIntent = PendingIntent.getActivity(this, 0, notificationIntent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
//
//        Notification notification = new NotificationCompat.Builder(this, "PrinterChannelId")
//                .setContentTitle("Zebra Printer Service")
//                .setContentText("The printer connection is active")
////                .setSmallIcon(R.drawable.ic_printer) // your icon
//                .setContentIntent(pendingIntent)
//                .build();
//
//        // Start the service in the foreground
//
//        startForeground(1, notification);
    }

    private void createNotificationChannel() {
//        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
//            NotificationChannel channel = new NotificationChannel(
//                    "PrinterChannelId",
//                    "Printer Service Channel",
//                    NotificationManager.IMPORTANCE_DEFAULT
//            );
//            NotificationManager manager = getSystemService(NotificationManager.class);
//            if (manager != null) {
//                manager.createNotificationChannel(channel);
//            }
//        }
    }

    @Override
    public void onDestroy() {
//        if (printerConnection != null && printerConnection.isConnected()) {
//            try {
//                printerConnection.close();
//            } catch (ConnectionException e) {
//                e.printStackTrace();
//            }
//        }
        super.onDestroy();
    }

    //    public static String getZplCode(Bitmap bitmap, Boolean addHeaderFooter, int rotation) {
//        ZPLConverter zp = new ZPLConverter();
//        zp.setCompressHex(true);
//        zp.setBlacknessLimitPercentage(50);
//        Bitmap grayBitmap = toGrayScale(bitmap, rotation);
//        return zp.convertFromImage(grayBitmap, addHeaderFooter);
//    }

//    public static Bitmap toGrayScale(Bitmap bmpOriginal, int rotation) {
//        int width, height;
//        bmpOriginal = rotateBitmap(bmpOriginal, rotation);
//        height = bmpOriginal.getHeight();
//        width = bmpOriginal.getWidth();
//        Bitmap grayScale = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
//        grayScale.eraseColor(Color.WHITE);
//        Canvas c = new Canvas(grayScale);
//        Paint paint = new Paint();
//        ColorMatrix cm = new ColorMatrix();
//        cm.setSaturation(0);
//        ColorMatrixColorFilter f = new ColorMatrixColorFilter(cm);
//        paint.setColorFilter(f);
//        c.drawBitmap(bmpOriginal, 0, 0, paint);
//        return grayScale;
//    }


//    public static Bitmap rotateBitmap(Bitmap source, float angle) {
//        Matrix matrix = new Matrix();
//        matrix.postRotate(angle);
//        return Bitmap.createBitmap(source, 0, 0, source.getWidth(), source.getHeight(), matrix, true);
//    }

//    public void setSettings(String settings) {
//        print(settings);
//    }

//    public void setDarkness(int darkness) {
//        String setting = "             ! U1 setvar \"print.tone\" \"" + darkness + "\"\n";
//        setSettings(setting);
//    }
//
//    public void setMediaType(String mediaType) {
//        String settings;
//        if (mediaType.equals("Label")) {
//            settings = "! U1 setvar \"media.type\" \"label\"\n" +
//                    "             ! U1 setvar \"media.sense_mode\" \"gap\"\n" +
//                    //    "             ! U1 setvar \"print.tone\" \"0\"\n" +
//                    "              ~jc^xa^jus^xz";
//        } else if (mediaType.equals("BlackMark")) {
//            settings = "! U1 setvar \"media.type\" \"label\"\n" +
//                    "             ! U1 setvar \"media.sense_mode\" \"bar\"\n" +
//                    //    "             ! U1 setvar \"print.tone\" \"0\"\n" +
//                    "              ~jc^xa^jus^xz";
//        } else {
//            settings = //"! U1 SPEED 4\n" +
//                    "      ! U1 setvar \"print.tone\" \"0\"\n" +
//                            "      ! U1 setvar \"media.type\" \"journal\"\n";
//            //   "      ! U1 setvar \"media.sense_mode\" \"bar\"" +
//            // " ~jc^xa^jus^xz";
//        }
//        setSettings(settings);
//    }
//
//    private void convertBase64ImageToZPLString(String data, int rotation, MethodChannel.Result result) {
//        try {
//            byte[] decodedString = Base64.decode(data, Base64.DEFAULT);
//            Bitmap decodedByte = BitmapFactory.decodeByteArray(decodedString, 0, decodedString.length);
//            result.success(Printer.getZplCode(decodedByte, false, rotation));
//        } catch (Exception e) {
//            result.error("-1", "Error", null);
//        }
//    }
//
//
//
//    private boolean checkIsLocationNetworkProviderIsOn() {
//        LocationManager lm = (LocationManager) context.getSystemService(Context.LOCATION_SERVICE);
//        try {
//            return lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER);
//        } catch (Exception ex) {
//            return false;
//        }
//    }
}