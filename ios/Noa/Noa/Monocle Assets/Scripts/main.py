import bluetooth
import camera,_camera
import graphics
import microphone
import touch
import states
import device
from audio import *
from photo import *

state = states.State()
gfx = graphics.Graphics()

def bluetooth_send_message(message):
    while True:
        try:
            bluetooth.send(message)
            break
        except OSError:
            pass

def bluetooth_message_handler(message):
    if state.current_state == state.WaitForResponse:
        if message.startswith("res:") or message.startswith("err:"):
            print_response(message)
        elif message.startswith("ick:"):
            state.after(0, state.WaitForTap)

    elif state.current_state == state.PrintResponse:
        gfx.append_response(message[4:].decode("utf-8"))

    elif state.current_state == state.WaitForTap:
        if message.startswith("res:") or message.startswith("err:"):
            print_response(message)

def touch_pad_handler(_):
    if state.current_state == state.WaitForTap:
        state.after(0, state.DetectSingleTap)
    elif state.current_state == state.DetectSingleTap:
        state.after(0, state.DetectDoubleTap)
    # elif state.current_state == state.WaitForResponse:
    #     state.after(0, state.AskToCancel)
    elif state.current_state == state.AskToCancel:
        state.after(0, state.WaitForTap)

def print_response(message):
    gfx.error_flag = message.startswith("err:")
    gfx.append_response(message[4:].decode("utf-8"))
    state.after(0, state.PrintResponse)

bluetooth.receive_callback(bluetooth_message_handler)
touch.callback(touch.EITHER, touch_pad_handler)
dev = False
while True:
    if state.current_state == state.Init:
        state.after(0, state.Welcome)

    elif state.current_state == state.Welcome:
        if state.on_entry():
            gfx.append_response(
                """Welcome to Remember for Monocle.\nStart the Remember iOS app."""
            )
        if bluetooth.connected() or dev:
            state.after(5000, state.Connected)

    elif state.current_state == state.Connected:
        if state.on_entry():
            gfx.clear_response()
            gfx.set_prompt("Connected")
        state.after(2000, state.WaitForTap)

    elif state.current_state == state.WaitForTap:
        if state.on_entry():
            bluetooth_send_message(b"rdy:")
            gfx.set_prompt("Tap and speak")

    # elif state.current_state == state.DetectSingleTap:
    #     if state.has_been() >= 250:
    #         if touch.state(touch.EITHER): # still holding, try detect hold
    #             state.after(0, state.DetectHold)
    #             _camera.wake()
    #         else:
    #             state.after(0, state.StartRecording)

    # elif state.current_state == state.DetectDoubleTap:
    #     battery_level = device.battery_level()  # Assuming this function returns the battery level
    #     gfx.display_battery_level(battery_level)
    #     state.after(2000, state.WaitForTap)  # Display the battery level for 2 seconds

    elif state.current_state == state.DetectDoubleTap:
        state.after(0, state.CaptureImage)
    elif state.current_state == state.DetectHold:
        if state.has_been() >= 1000 and touch.state(touch.EITHER):
            state.after(0, state.CaptureImage)
        # elif not touch.state(touch.EITHER):
        #     _camera.sleep()
        #     state.after(0, state.WaitForTap)

    # elif state.current_state == state.StartRecording:
    #     start_recording(state, gfx, bluetooth_send_message)

    # elif state.current_state == state.SendAudio:
    #     send_audio(state, gfx, bluetooth_send_message)

    # elif state.current_state == state.WaitForResponse:
    #     gfx.set_prompt("Waiting for openAI")

    elif state.current_state == state.AskToCancel:
        gfx.set_prompt("Cancel?")
        state.after(3000, state.previous_state)

    # elif state.current_state == state.PrintResponse:
    #     gfx.set_prompt("")
    #     if gfx.done_printing:
    #         state.after(0, state.WaitForTap)

    elif state.current_state == state.CaptureImage:
        capture_image(state, gfx, bluetooth_send_message)

    elif state.current_state == state.SendImage:
        send_image(state, gfx, bluetooth_send_message)

    gfx.run()
