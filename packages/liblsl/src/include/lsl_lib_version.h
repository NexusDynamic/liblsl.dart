#ifndef LSL_LIBRARY_INFO_STR
#define MSTR_EXPAND(tok) #tok
#define MSTR(tok) MSTR_EXPAND(tok)

#define LSL_LIBTYPE_DART link:SHARED
// Concatenate strings without space, using proper formatting of /
#define LSL_LIBRARY_INFO_STR MSTR(LSL_VERSION_INFO) "/" MSTR(LSL_LIBTYPE_DART)
#endif
