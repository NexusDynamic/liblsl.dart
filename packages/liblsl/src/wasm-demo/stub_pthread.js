// Stub library to provide missing pthread functions
mergeInto(LibraryManager.library, {
  pthread_getname_np: function() {
    return 0; // Return success
  }
});