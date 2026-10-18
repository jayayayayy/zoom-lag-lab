# Testing and verification

## Automated regression checks

From the repository root, run:

```sh
python3 source/test_helper.py
```

The checks replace privileged network commands with mocks and do not change your connection. They cover timed completion, setup failures, interface validation, idle restore, early Stop, recovery after a stopped worker, cleanup retry, existing PF refusal, repeating intervals, continuous operation, and restoration after the controlling process exits.

## Check behavior in your own private meeting

1. Join a private meeting from this Mac and a second device. Keep the second device’s microphone and camera off to avoid feedback.
2. Establish a baseline using Zoom’s Audio and Video statistics. A local camera preview is not proof of received quality.
3. Select Choppy, click Start lag, and observe both the received stream and Zoom’s media statistics. Use Severe if needed.
4. Click Restore connection and verify the media and ordinary internet access recover.

Both clients on the same Mac share its impaired connection. A separate receiving device is better for judging the actual visible and audible effect. Zoom may adapt its codec, conceal loss, reduce quality, or disconnect; exact freezes are not guaranteed.

Compatibility can vary with OS release and other firewall/network software. Verify the behavior on your own configuration before relying on it.
