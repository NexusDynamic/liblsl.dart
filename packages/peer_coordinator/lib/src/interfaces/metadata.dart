abstract interface class IHasMetadata {
  /// Returns the metadata associated with this resource.
  Map<String, dynamic> get metadata;

  // @TODO: add later
  // Map<String, String>? get customMetadata;
  // Sets the user-specifiable metadata for this resource.
  // this does not have to be the entire [metadata] map, but can be a subset.
  // This depends on the implementation
  // set customMetadata(Map<String, String>? metadata);

  /// Returns a specific metadata value by key.
  dynamic getMetadata(String key, {dynamic defaultValue});
}
