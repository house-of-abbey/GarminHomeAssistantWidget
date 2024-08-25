//-----------------------------------------------------------------------------------
//
// Distributed under MIT Licence
//   See https://github.com/house-of-abbey/GarminHomeAssistantWidget/blob/main/LICENSE.
//
//-----------------------------------------------------------------------------------
//
// GarminHomeAssistantWidget is a Garmin IQ widget written in Monkey C. The source code is provided at:
//            https://github.com/house-of-abbey/GarminHomeAssistantWidget.
//
// P A Abbey & J D Abbey & Someone0nEarth, 31 October 2023
//
//
// Description:
//
// The background service delegate currently just reports the Garmin watch's battery
// level.
//
//-----------------------------------------------------------------------------------

using Toybox.Lang;
using Toybox.Application.Properties;
using Toybox.Background;
using Toybox.System;
using Toybox.Activity;

(:background)
class BackgroundServiceDelegate extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onReturnBatteryUpdate(responseCode as Lang.Number, data as Null or Lang.Dictionary or Lang.String) as Void {
        // System.println("BackgroundServiceDelegate onReturnBatteryUpdate() Response Code: " + responseCode);
        // System.println("BackgroundServiceDelegate onReturnBatteryUpdate() Response Data: " + data);
        Background.exit(null);
    }

    function onActivityCompleted(activity as { :sport as Activity.Sport, :subSport as Activity.SubSport }) as Void {
        if (!System.getDeviceSettings().phoneConnected) {
            // System.println("BackgroundServiceDelegate onActivityCompleted(): No Phone connection, skipping API call.");
        } else if (!System.getDeviceSettings().connectionAvailable) {
            // System.println("BackgroundServiceDelegate onActivityCompleted(): No Internet connection, skipping API call.");
        } else {
            // Ensure we're logging completion, i.e. ignore 'activity' parameter
            // System.println("BackgroundServiceDelegate onActivityCompleted(): Event triggered");
            doUpdate(-1, -1);
        }
    }

    function onTemporalEvent() as Void {
        if (!System.getDeviceSettings().phoneConnected) {
            // System.println("BackgroundServiceDelegate onTemporalEvent(): No Phone connection, skipping API call.");
        } else if (!System.getDeviceSettings().connectionAvailable) {
            // System.println("BackgroundServiceDelegate onTemporalEvent(): No Internet connection, skipping API call.");
        } else {
            var activity     = null;
            var sub_activity = null;
            if ((Activity has :getActivityInfo) and (Activity has :getProfileInfo)) {
                activity     = Activity.getProfileInfo().sport;
                sub_activity = Activity.getProfileInfo().subSport;
                // We need to check if we are actually tracking any activity as the enumerated type does not include "No Sport".
                if ((Activity.getActivityInfo() != null) and
                    ((Activity.getActivityInfo().elapsedTime == null) or
                        (Activity.getActivityInfo().elapsedTime == 0))) {
                    // Indicate no activity with -1, not part of Garmin's activity codes.
                    // https://developer.garmin.com/connect-iq/api-docs/Toybox/Activity.html#Sport-module
                    activity     = -1;
                    sub_activity = -1;
                }
            }
            // System.println("BackgroundServiceDelegate onTemporalEvent(): Event triggered, activity = " + activity + " sub_activity = " + sub_activity);
            doUpdate(activity, sub_activity);
        }
    }

     private function doUpdate(activity as Lang.Number or Null, sub_activity as Lang.Number or Null) {
        // System.println("BackgroundServiceDelegate onTemporalEvent(): Making API call.");
        var position = Position.getInfo();
        // System.println("BackgroundServiceDelegate onTemporalEvent(): GPS      : " + position.position.toDegrees());
        // System.println("BackgroundServiceDelegate onTemporalEvent(): Speed    : " + position.speed);
        // System.println("BackgroundServiceDelegate onTemporalEvent(): Course   : " + position.heading + " radians (" + (position.heading * 180 / Math.PI) + "°)");
        // System.println("BackgroundServiceDelegate onTemporalEvent(): Altitude : " + position.altitude);
        // System.println("BackgroundServiceDelegate onTemporalEvent(): Battery  : " + System.getSystemStats().battery);
        // System.println("BackgroundServiceDelegate onTemporalEvent(): Charging : " + System.getSystemStats().charging);
        // System.println("BackgroundServiceDelegate onTemporalEvent(): Activity : " + Activity.getProfileInfo().name);

        // Don't use Settings.* here as the object lasts < 30 secs and is recreated each time the background service is run

        if (position.accuracy != Position.QUALITY_NOT_AVAILABLE && position.accuracy != Position.QUALITY_LAST_KNOWN) {
            var accuracy = 0;
            switch (position.accuracy) {
                case Position.QUALITY_POOR:
                    accuracy = 500;
                    break;
                case Position.QUALITY_USABLE:
                    accuracy = 100;
                    break;
                case Position.QUALITY_GOOD:
                    accuracy = 10;
                    break;
            }

            var data = { "gps_accuracy" => accuracy };
            // Only add the non-null fields as all the values are optional in Home Assistant, and it avoid submitting fake values.
            if (position.position != null) {
                data.put("gps", position.position.toDegrees());
            }
            if (position.speed != null) {
                data.put("speed", Math.round(position.speed));
            }
            if (position.heading != null) {
                data.put("course", Math.round(position.heading * 180 / Math.PI));
            }
            if (position.altitude != null) {
                data.put("altitude", Math.round(position.altitude));
            }
            // System.println("BackgroundServiceDelegate onTemporalEvent(): data = " + data.toString());

            Communications.makeWebRequest(
                (Properties.getValue("api_url") as Lang.String) + "/webhook/" + (Properties.getValue("webhook_id") as Lang.String),
                {
                    "type" => "update_location",
                    "data" => data,
                },
                {
                    :method       => Communications.HTTP_REQUEST_METHOD_POST,
                    :headers      => {
                        "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
                    },
                    :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
                },
                method(:onReturnBatteryUpdate)
            );
        }
        var data = [
            {
                "state"     => System.getSystemStats().battery,
                "type"      => "sensor",
                "unique_id" => "battery_level"
            },
            {
                "state"     => System.getSystemStats().charging,
                "type"      => "binary_sensor",
                "unique_id" => "battery_is_charging"
            }
        ];
        if (activity != null) {
            data.add({
                "state"     => activity,
                "type"      => "sensor",
                "unique_id" => "activity"
            });
        }
        if (sub_activity != null) {
            data.add({
                "state"     => sub_activity,
                "type"      => "sensor",
                "unique_id" => "sub_activity"
            });
        }
        Communications.makeWebRequest(
            (Properties.getValue("api_url") as Lang.String) + "/webhook/" + (Properties.getValue("webhook_id") as Lang.String),
            {
                "type" => "update_sensor_states",
                "data" => data
            },
            {
                :method       => Communications.HTTP_REQUEST_METHOD_POST,
                :headers      => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onReturnBatteryUpdate)
        );
    }

}
