cat /etc/passwd | grep "/bin/false" | grep "/home" | sed 's/:.*//'
