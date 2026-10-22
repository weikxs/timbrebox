import '../model/search_models.dart';
import '../model/source_descriptor.dart';

abstract interface class MusicSource {
  SourceDescriptor get descriptor;

  Future<SearchPage> search(SearchRequest request);
}
