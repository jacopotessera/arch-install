# Start X at login
if status is-login
  if test -z $DISPLAY; and test (tty) = "/dev/tty1"
    #WLR_NO_HARDWARE_CURSORS=1 LIBSEAT_BACKEND=logind WLR_RENDERER_ALLOW_SOFTWARE=1
    sway
  end
end
