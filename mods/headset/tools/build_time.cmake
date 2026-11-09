# Writes this build's time for src/plugin/main.cpp to log. CMakeLists.txt runs it on every build.
string(TIMESTAMP now "%Y-%m-%d %H:%M UTC" UTC)
file(WRITE "${OUT}" "#define HS_BUILT \"${now}\"\n")
