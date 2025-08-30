class ReadingsSearchState {
  String? searchQuery;
  DateTime? startDate;
  DateTime? endDate;
  double? minConsumption;
  double? maxConsumption;
  bool? isManual;
  String sortBy;
  bool sortAscending;

  ReadingsSearchState({
    this.searchQuery,
    this.startDate,
    this.endDate,
    this.minConsumption,
    this.maxConsumption,
    this.isManual,
    this.sortBy = 'date',
    this.sortAscending = false,
  });

  ReadingsSearchState copyWith({
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
    double? minConsumption,
    double? maxConsumption,
    bool? isManual,
    String? sortBy,
    bool? sortAscending,
  }) {
    return ReadingsSearchState(
      searchQuery: searchQuery ?? this.searchQuery,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      minConsumption: minConsumption ?? this.minConsumption,
      maxConsumption: maxConsumption ?? this.maxConsumption,
      isManual: isManual ?? this.isManual,
      sortBy: sortBy ?? this.sortBy,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }

  bool get hasFilters =>
      searchQuery != null && searchQuery!.isNotEmpty ||
      startDate != null ||
      endDate != null ||
      minConsumption != null ||
      maxConsumption != null ||
      isManual != null ||
      sortBy != 'date' ||
      sortAscending;

  void clearFilters() {
    searchQuery = null;
    startDate = null;
    endDate = null;
    minConsumption = null;
    maxConsumption = null;
    isManual = null;
    sortBy = 'date';
    sortAscending = false;
  }
}