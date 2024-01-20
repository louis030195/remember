import bluetooth
import camera
import states

def capture_image(state, gfx, send_message):
    if state.on_entry():
        camera.capture()
        send_message(b"ist:")
        gfx.clear_response()
        gfx.set_prompt("Camera ON")
    state.after(250, state.SendImage)

def send_image(state, gfx, send_message):
    if state.on_entry():
        gfx.clear_response()
        state.current_state.bytes_sent = 0
    samples = bluetooth.max_length() - 4
    chunk = camera.read(samples)
    if chunk == None:
        send_message(b"ien:")
        # loop capture image every 2 secs
        state.after(2000, state.CaptureImage)
    else:
        send_message(b"idt:" + chunk)
        state.current_state.bytes_sent += len(chunk)
        benchmark_size = 64000
        percent = state.current_state.bytes_sent / benchmark_size
        gfx.set_prompt("[-]" if percent > 0.5 else "[|]")
    # if chunk == None:
    #     # Finished, start microphone recording next. The microphone recording state will
    #     # send the "ien:" command!
    #     state.after(0, state.StartRecording)
    # else:
    #     send_message(b"idt:" + chunk)
    #     state.current_state.bytes_sent += len(chunk)
    #     benchmark_size = 64000
    #     percent = state.current_state.bytes_sent / benchmark_size
    #     if percent > 0.8:
    #         gfx.set_prompt("Sending photo [=====]")
    #     elif percent > 0.6:
    #         gfx.set_prompt("Sending photo [==== ]")
    #     elif percent > 0.4:
    #         gfx.set_prompt("Sending photo [===  ]")
    #     elif percent > 0.2:
    #         gfx.set_prompt("Sending photo [==   ]")
    #     else:
    #         gfx.set_prompt("Sending photo [=    ]")
