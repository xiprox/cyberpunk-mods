# Writes a header that defines NAME as this build's time, for a mod's log line: test builds between releases share a
# version number, and the time says which build ran. A mod's CMakeLists.txt runs it on every build:
#   cmake -DOUT=<header> -DNAME=<macro> -P tools/build-time.cmake
string(TIMESTAMP now "%Y-%m-%d %H:%M UTC" UTC)
file(WRITE "${OUT}" "#define ${NAME} \"${now}\"\n")
