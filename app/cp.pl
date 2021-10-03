my @args = ( 'cat -n ~/token | sed -n 1p ~/token | xclip -selection "clipboard" -rmlastnl' );

exec @args;               # subject to shell escapes
                            # if @args == 1
exec { $args[0] } @args;  # safe even with one-arg list
