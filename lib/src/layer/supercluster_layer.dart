import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:flutter_map_marker_popup/extension_api.dart';
import 'package:flutter_map_marker_popup/flutter_map_marker_popup.dart';
import 'package:flutter_map_supercluster/src/controller/supercluster_state.dart';
import 'package:flutter_map_supercluster/src/layer/loading_overlay.dart';
import 'package:flutter_map_supercluster/src/layer/supercluster_config.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supercluster/supercluster.dart';

import '../controller/marker_event.dart';
import '../controller/supercluster_controller.dart';
import '../controller/supercluster_controller_impl.dart';
import '../options/animation_options.dart';
import '../options/popup_options.dart';
import '../widget/cluster_widget.dart';
import '../widget/marker_widget.dart';
import '../widget/rotate.dart';
import 'center_zoom_controller.dart';
import 'cluster_data.dart';
import 'map_calculator.dart';

typedef ClusterWidgetBuilder = Widget Function(
  BuildContext context,
  LatLng position,
  int markerCount,
  ClusterDataBase? extraClusterData,
);

class SuperclusterLayer extends StatefulWidget {
  final bool _isMutableSupercluster;

  /// Cluster builder
  final ClusterWidgetBuilder builder;

  /// Controller for managing [Marker]s and listening to changes.
  final SuperclusterController? controller;

  /// Initial list of markers, additions/removals must be made using the
  /// [controller].
  final List<Marker> initialMarkers;

  /// An optional callback which allows you to perform the creation of the
  /// supercluster index in a separate isolate. The default behaviour is to run
  /// the creation in another isolate using Flutter's `compute`.
  ///
  /// Using `compute` incurs a slight delay as it creates a new isolate. If you
  /// don't mind the index loading happening on the main isolate (which can
  /// block the UI) then set this callback to:
  ///
  /// (superclusterConfig) async => createSupercluster(superclusterConfig)
  ///
  /// Similarly you can maintain an isolate to be used for index creation or
  /// use a package which does this for you to avoid waiting for the isolate to
  /// be created every time a load occurs. In that case pass them the
  /// [superclusterConfig] and the [createSupercluster] functions.
  final Future<Supercluster<Marker>> Function(SuperclusterConfig superclusterConfig)?
      wrapIndexCreation;

  /// The minimum number of points required to form a cluster, if there is less
  /// than this number of points within the [maxClusterRadius] the markers will
  /// be left unclustered.
  final int? minimumClusterSize;

  /// The maximum radius in pixels that a cluster can cover.
  final int maxClusterRadius;

  /// Implement this function to extract extra data from Markers which can be
  /// used in the [builder] and [computeSize].
  final ClusterDataBase Function(Marker marker)? clusterDataExtractor;

  /// Function to call when a Marker is tapped
  final void Function(Marker)? onMarkerTap;

  /// A builder used to override the override which is displayed whilst the
  /// supercluster index is being built.
  final WidgetBuilder? loadingOverlayBuilder;

  /// Popup's options that show when tapping markers or via the PopupController.
  final PopupOptions? popupOptions;

  /// If true markers will be counter rotated to the map rotation
  final bool? rotate;

  /// The origin of the coordinate system (relative to the upper left corner of
  /// this render object) in which to apply the matrix.
  ///
  /// Setting an origin is equivalent to conjugating the transform matrix by a
  /// translation. This property is provided just for convenience.
  final Offset? rotateOrigin;

  /// The alignment of the origin, relative to the size of the box.
  ///
  /// This is equivalent to setting an origin based on the size of the box.
  /// If it is specified at the same time as the [rotateOrigin], both are applied.
  ///
  /// An [AlignmentDirectional.centerStart] value is the same as an [Alignment]
  /// whose [Alignment.x] value is `-1.0` if [Directionality.of] returns
  /// [TextDirection.ltr], and `1.0` if [Directionality.of] returns
  /// [TextDirection.rtl].	 Similarly [AlignmentDirectional.centerEnd] is the
  /// same as an [Alignment] whose [Alignment.x] value is `1.0` if
  /// [Directionality.of] returns	 [TextDirection.ltr], and `-1.0` if
  /// [Directionality.of] returns [TextDirection.rtl].
  final AlignmentGeometry? rotateAlignment;

  /// Cluster size
  final Size clusterWidgetSize;

  /// Cluster anchor
  final AnchorPos? anchor;

  /// Control cluster zooming (triggered by cluster tap) animation. Use
  /// [AnimationOptions.none] to disable animation. See
  ///  [AnimationOptions.animate] for more information on animation options.
  final AnimationOptions clusterZoomAnimation;

  /// If true then whenever the aggregated cluster data changes (that is, the
  /// combined cluster data of all Markers as calculated by
  /// [clusterDataExtractor]) then the new value will be added to the
  /// [controller]'s [aggregatedClusterDataStream].
  final bool calculateAggregatedClusterData;

  const SuperclusterLayer.immutable({
    Key? key,
    SuperclusterImmutableController? this.controller,
    required this.builder,
    this.initialMarkers = const [],
    this.onMarkerTap,
    this.minimumClusterSize,
    this.maxClusterRadius = 80,
    this.clusterDataExtractor,
    this.calculateAggregatedClusterData = false,
    this.clusterWidgetSize = const Size(30, 30),
    this.clusterZoomAnimation = const AnimationOptions.animate(
      curve: Curves.linear,
      velocity: 1,
    ),
    this.loadingOverlayBuilder,
    this.wrapIndexCreation,
    this.popupOptions,
    this.rotate,
    this.rotateOrigin,
    this.rotateAlignment,
    this.anchor,
  })  : _isMutableSupercluster = false,
        super(key: key);

  const SuperclusterLayer.mutable({
    Key? key,
    SuperclusterMutableController? this.controller,
    required this.builder,
    this.initialMarkers = const [],
    this.onMarkerTap,
    this.minimumClusterSize,
    this.maxClusterRadius = 80,
    this.clusterDataExtractor,
    this.calculateAggregatedClusterData = false,
    this.clusterWidgetSize = const Size(30, 30),
    this.clusterZoomAnimation = const AnimationOptions.animate(
      curve: Curves.linear,
      velocity: 1,
    ),
    this.loadingOverlayBuilder,
    this.wrapIndexCreation,
    this.popupOptions,
    this.rotate,
    this.rotateOrigin,
    this.rotateAlignment,
    this.anchor,
  })  : _isMutableSupercluster = true,
        super(key: key);

  @override
  State<SuperclusterLayer> createState() => _SuperclusterLayerState();
}

class _SuperclusterLayerState extends State<SuperclusterLayer> with TickerProviderStateMixin {
  static const defaultMinZoom = 1;
  static const defaultMaxZoom = 20;

  FlutterMapState? _mapState;

  late int minZoom;
  late int maxZoom;
  late MapCalculator _mapCalculator;

  late CenterZoomController _centerZoomController;
  StreamSubscription<MarkerEvent>? _controllerSubscription;
  StreamSubscription<void>? _movementStreamSubscription;
  int? _hidePopupIfZoomLessThan;

  PopupState? _popupState;

  CancelableCompleter<Supercluster<Marker>> _superclusterCompleter = CancelableCompleter();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final previousMapState = _mapState;
    final mapState = FlutterMapState.maybeOf(context)!;
    _mapState = mapState;

    bool firstInitialization = previousMapState == null;
    bool mapStateNewOrChanged = firstInitialization || mapState != previousMapState;

    final oldMinZoom = firstInitialization ? null : minZoom;
    final oldMaxZoom = firstInitialization ? null : maxZoom;
    minZoom = mapState.options.minZoom?.ceil() ?? defaultMinZoom;
    maxZoom = mapState.options.maxZoom?.ceil() ?? defaultMaxZoom;

    bool zoomsChanged = !firstInitialization && oldMinZoom != minZoom || oldMaxZoom != maxZoom;

    if (mapStateNewOrChanged) {
      _mapCalculator = MapCalculator(
        mapState: mapState,
        clusterWidgetSize: widget.clusterWidgetSize,
        clusterAnchorPos: widget.anchor,
      );
      if (!firstInitialization) _centerZoomController.dispose();
      _centerZoomController = CenterZoomController(
        vsync: this,
        mapState: mapState,
        animationOptions: widget.clusterZoomAnimation,
      );
      _controllerSubscription?.cancel();
      _controllerSubscription = widget.controller == null
          ? null
          : (widget.controller! as SuperclusterControllerImpl)
              .stream
              .listen((markerEvent) => _onMarkerEvent(markerEvent));

      _movementStreamSubscription?.cancel();
      if (widget.popupOptions != null) {
        _movementStreamSubscription =
            mapState.mapController.mapEventStream.listen((_) => _onMove(mapState));
      }
    }

    if (mapStateNewOrChanged || zoomsChanged) {
      if (!firstInitialization) {
        debugPrint('WARNING: Changes to the FlutterMapState have caused a rebuild of '
            'the Supercluster clusters. This can be a slow operation and '
            'should be avoided whenever possible.');
      }
      _initializeClusterManager(
        firstInitialization
            ? Future.value(widget.initialMarkers)
            : _superclusterCompleter.operation.value
                .then((supercluster) => supercluster.getLeaves().toList()),
      );
    }
  }

  @override
  void didUpdateWidget(SuperclusterLayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    final mapState = _mapState!;

    if (oldWidget._isMutableSupercluster != widget._isMutableSupercluster ||
        oldWidget.controller != widget.controller) {
      _onControllerChange(
        oldWidget.controller as SuperclusterControllerImpl?,
        widget.controller as SuperclusterControllerImpl?,
      );
    }

    if (oldWidget._isMutableSupercluster != widget._isMutableSupercluster ||
        oldWidget.maxClusterRadius != widget.maxClusterRadius ||
        oldWidget.minimumClusterSize != widget.minimumClusterSize ||
        oldWidget.calculateAggregatedClusterData != widget.calculateAggregatedClusterData) {
      debugPrint('WARNING: Changes to the Supercluster options have caused a rebuild '
          'of the Supercluster clusters. This can be a slow operation and '
          'should be avoided whenever possible.');
      _initializeClusterManager(_superclusterCompleter.operation
          .valueOrCancellation()
          .then((supercluster) => supercluster?.getLeaves().toList() ?? []));
    }

    if (oldWidget.clusterZoomAnimation != widget.clusterZoomAnimation) {
      _centerZoomController.animationOptions = widget.clusterZoomAnimation;
    }

    if (widget.popupOptions != oldWidget.popupOptions) {
      _movementStreamSubscription?.cancel();
      if (widget.popupOptions != null) {
        _movementStreamSubscription =
            mapState.mapController.mapEventStream.listen((_) => _onMove(mapState));
      }
    }
  }

  @override
  void dispose() {
    _movementStreamSubscription?.cancel();
    _centerZoomController.dispose();
    _controllerSubscription?.cancel();
    super.dispose();
  }

  void _initializeClusterManager(Future<List<Marker>> markersFuture) {
    (widget.controller as SuperclusterControllerImpl)
        .updateState(const SuperclusterState(loading: true, aggregatedClusterData: null));

    final supercluster = markersFuture.catchError((_) => <Marker>[]).then((markers) {
      final superclusterConfig = SuperclusterConfig(
        isMutableSupercluster: widget._isMutableSupercluster,
        markers: markers,
        minZoom: minZoom,
        maxZoom: maxZoom,
        maxClusterRadius: widget.maxClusterRadius,
        minimumClusterSize: widget.minimumClusterSize,
        innerClusterDataExtractor: widget.clusterDataExtractor,
      );

      if (_superclusterCompleter.isCompleted || _superclusterCompleter.isCanceled) {
        setState(() {
          _superclusterCompleter = CancelableCompleter();
        });
      }

      final newSupercluster = widget.wrapIndexCreation?.call(superclusterConfig) ??
          compute(createSupercluster, superclusterConfig);

      _superclusterCompleter.complete(newSupercluster);
      _superclusterCompleter.operation.value.then((supercluster) {
        _onMarkersChange();
        widget.popupOptions?.popupController.hideAllPopups();
      });

      return newSupercluster;
    });

    if (widget.controller != null) {
      (widget.controller as SuperclusterControllerImpl).setSupercluster(supercluster);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapState = FlutterMapState.maybeOf(context)!;

    return _wrapWithPopupStateIfPopupsEnabled(
      (popupState) => Stack(
        children: [
          _buildClustersAndMarkers(mapState),
          if (widget.popupOptions != null)
            PopupLayer(
              popupState: _popupState!,
              popupBuilder: widget.popupOptions!.popupBuilder,
              popupSnap: widget.popupOptions!.popupSnap,
              popupController: widget.popupOptions!.popupController,
              popupAnimation: widget.popupOptions!.popupAnimation,
              markerRotate: widget.popupOptions!.markerRotate,
            ),
          LoadingOverlay(
            superclusterFuture: _superclusterCompleter.operation.value,
            loadingOverlayBuilder: widget.loadingOverlayBuilder,
          ),
        ],
      ),
    );
  }

  Widget _wrapWithPopupStateIfPopupsEnabled(Widget Function(PopupState? popupState) builder) {
    if (widget.popupOptions == null) return builder(null);

    return PopupStateWrapper(builder: (context, popupState) {
      _popupState = popupState;
      if (widget.popupOptions!.selectedMarkerBuilder != null) {
        context.watch<PopupState>();
      }
      return builder(popupState);
    });
  }

  Widget _buildClustersAndMarkers(FlutterMapState mapState) {
    final paddedBounds = _mapCalculator.paddedMapBounds();
    return FutureBuilder<Supercluster<Marker>>(
      future: _superclusterCompleter.operation.value,
      builder: (context, snapshot) {
        final supercluster = snapshot.data;
        if (supercluster == null) return const SizedBox.shrink();

        return Stack(children: [
          ...(supercluster.search(
            paddedBounds.west,
            paddedBounds.south,
            paddedBounds.east,
            paddedBounds.north,
            mapState.zoom.ceil(),
          )..sort(_clustersLast))
              .map((layerElement) => _buildMarkerOrCluster(mapState, layerElement)),
        ]);
      },
    );
  }

  Widget _buildMarkerOrCluster(
    FlutterMapState mapState,
    LayerElement<Marker> layerElement,
  ) {
    return layerElement.handle(
      cluster: (cluster) => _buildMarkerClusterLayer(mapState, cluster),
      point: (point) => _buildMarkerLayer(mapState, point),
    );
  }

  Widget _buildMarkerClusterLayer(
    FlutterMapState mapState,
    LayerCluster<Marker> cluster,
  ) {
    return ClusterWidget(
      mapCalculator: _mapCalculator,
      cluster: cluster,
      builder: widget.builder,
      onTap: _onClusterTap(cluster),
      size: widget.clusterWidgetSize,
      rotate: widget.rotate != true
          ? null
          : Rotate(
              angle: -mapState.rotationRad,
              origin: widget.rotateOrigin,
              alignment: widget.rotateAlignment,
            ),
    );
  }

  Widget _buildMarkerLayer(
    FlutterMapState mapState,
    LayerPoint<Marker> mapPoint,
  ) {
    final marker = mapPoint.originalPoint;

    var markerBuilder = marker.builder;
    final popupOptions = widget.popupOptions;
    if (popupOptions?.selectedMarkerBuilder != null &&
        _popupState!.selectedMarkers.contains(marker)) {
      markerBuilder = ((context) => widget.popupOptions!.selectedMarkerBuilder!(context, marker));
    }

    return MarkerWidget(
      mapCalculator: _mapCalculator,
      marker: marker,
      markerBuilder: markerBuilder,
      onTap: _onMarkerTap(mapPoint),
      size: Size(marker.width, marker.height),
      rotate: marker.rotate != true && widget.rotate != true
          ? null
          : Rotate(
              angle: -mapState.rotationRad,
              origin: marker.rotateOrigin ?? widget.rotateOrigin,
              alignment: marker.rotateAlignment ?? widget.rotateAlignment,
            ),
    );
  }

  VoidCallback _onClusterTap(LayerCluster<Marker> cluster) {
    return () {
      _centerZoomController.moveTo(
        CenterZoom(
          center: LatLng(cluster.latitude, cluster.longitude),
          zoom: cluster.highestZoom + 1,
        ),
      );
    };
  }

  VoidCallback _onMarkerTap(LayerPoint<Marker> mapPoint) {
    return () {
      if (widget.popupOptions != null) {
        assert(_popupState != null);

        debugPrint(
            'Tapped (${mapPoint.originalPoint.point}): ${identityHashCode(mapPoint.originalPoint)}');
        final popupOptions = widget.popupOptions!;
        popupOptions.markerTapBehavior.apply(
          mapPoint.originalPoint,
          _popupState!,
          popupOptions.popupController,
        );
        _hidePopupIfZoomLessThan = mapPoint.lowestZoom;

        if (popupOptions.selectedMarkerBuilder != null) setState(() {});
      }

      widget.onMarkerTap?.call(mapPoint.originalPoint);
    };
  }

  void _onMove(FlutterMapState mapState) {
    if (_hidePopupIfZoomLessThan != null && mapState.zoom.ceil() < _hidePopupIfZoomLessThan!) {
      widget.popupOptions?.popupController.hideAllPopups();
      _hidePopupIfZoomLessThan = null;
    }
  }

  void _onMarkersChange() {
    if (widget.controller == null) return;

    _superclusterCompleter.operation.value.then((supercluster) {
      final aggregatedClusterData =
          widget.calculateAggregatedClusterData ? supercluster.aggregatedClusterData() : null;
      final clusterData =
          aggregatedClusterData == null ? null : (aggregatedClusterData as ClusterData);
      (widget.controller as SuperclusterControllerImpl).updateState(
        SuperclusterState(
          loading: false,
          aggregatedClusterData: clusterData,
        ),
      );
    });
  }

  void _onControllerChange(
      SuperclusterControllerImpl? oldController, SuperclusterControllerImpl? newController) {
    _controllerSubscription?.cancel();
    _controllerSubscription =
        newController?.stream.listen((markerEvent) => _onMarkerEvent(markerEvent));

    if (oldController != null) {
      oldController.removeSupercluster();
    }
    if (newController != null) {
      newController.setSupercluster(_superclusterCompleter.operation.value);
    }
  }

  void _onMarkerEvent(MarkerEvent markerEvent) {
    if (markerEvent is AddMarkerEvent) {
      _superclusterCompleter.operation.then((supercluster) {
        (supercluster as SuperclusterMutable<Marker>).insert(markerEvent.marker);
        _onMarkersChange();
      });
    } else if (markerEvent is RemoveMarkerEvent) {
      _superclusterCompleter.operation.then((supercluster) {
        final removed = (supercluster as SuperclusterMutable<Marker>).remove(markerEvent.marker);
        if (removed) _onMarkersChange();
      });
    } else if (markerEvent is ReplaceAllMarkerEvent) {
      _initializeClusterManager(Future.value(markerEvent.markers));
    } else if (markerEvent is ModifyMarkerEvent) {
      _superclusterCompleter.operation.then((supercluster) {
        final modified = (supercluster as SuperclusterMutable<Marker>).modifyPointData(
          markerEvent.oldMarker,
          markerEvent.newMarker,
          updateParentClusters: markerEvent.updateParentClusters,
        );

        if (modified) _onMarkersChange();
      });
    } else {
      throw 'Unknown $MarkerEvent type ${markerEvent.runtimeType}';
    }

    setState(() {});
  }

  int _clustersLast(LayerElement<Marker> a, LayerElement<Marker> b) {
    return a.handle(
      cluster: (_) => b.handle(
        cluster: (_) => 0,
        point: (_) => 1,
      ),
      point: (pA) => b.handle(
        cluster: (_) => -1,
        point: (_) => 0,
      ),
    );
  }
}
