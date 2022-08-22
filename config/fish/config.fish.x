if status is-login
  if test -z $DISPLAY; and test (tty) = "/dev/tty1"
    startx
  end
end
