import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_supercluster/flutter_map_supercluster.dart';
import 'package:flutter_map_supercluster_example/drawer.dart';
import 'package:latlong2/latlong.dart';

class MutableClusteringPage extends StatefulWidget {
  static const String route = 'clusteringPage';

  const MutableClusteringPage({Key? key}) : super(key: key);

  @override
  _MutableClusteringPageState createState() => _MutableClusteringPageState();
}

class _MutableClusteringPageState extends State<MutableClusteringPage> {
  late final SuperclusterMutableController _superclusterController;

  late List<Marker> markers;
  late int pointIndex;
  List points = [
    LatLng(51.5, -0.09),
    LatLng(49.8566, 3.3522),
  ];
  int? tappedMarkerIndex;

  @override
  void initState() {
    _superclusterController = SuperclusterMutableController();
    pointIndex = 0;
    markers = [
      Marker(
        anchorPos: AnchorPos.align(AnchorAlign.center),
        height: 30,
        width: 30,
        point: points[pointIndex],
        builder: (ctx) => const Icon(Icons.pin_drop),
      ),
      Marker(
        anchorPos: AnchorPos.align(AnchorAlign.center),
        height: 30,
        width: 30,
        point: LatLng(53.3498, -6.2603),
        builder: (ctx) => const Icon(Icons.pin_drop),
      ),
      Marker(
        anchorPos: AnchorPos.align(AnchorAlign.center),
        height: 30,
        width: 30,
        point: LatLng(53.3488, -6.2613),
        builder: (ctx) => const Icon(Icons.pin_drop),
      ),
    ];

    super.initState();
  }

  @override
  void dispose() {
    _superclusterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clustering Page'),
        actions: [
          StreamBuilder<SuperclusterState>(
              stream: _superclusterController.stateStream,
              builder: (context, snapshot) {
                final data = snapshot.data;
                final String markerCountLabel;
                if (data == null ||
                    data.loading ||
                    data.aggregatedClusterData == null) {
                  markerCountLabel = '...';
                } else {
                  markerCountLabel =
                      data.aggregatedClusterData!.markerCount.toString();
                }

                return Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: Text('Total markers: $markerCountLabel'),
                  ),
                );
              }),
        ],
      ),
      drawer: buildDrawer(context, MutableClusteringPage.route),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          pointIndex++;
          if (pointIndex >= points.length) {
            pointIndex = 0;
          }
          setState(() {
            markers[0] = Marker(
              point: points[pointIndex],
              anchorPos: AnchorPos.align(AnchorAlign.center),
              height: 30,
              width: 30,
              builder: (ctx) => const Icon(Icons.pin_drop),
            );
            markers = List.from(markers);
          });
        },
        child: const Icon(Icons.refresh),
      ),
      body: FlutterMap(
        options: MapOptions(
          center: points[0],
          zoom: 5,
          maxZoom: 15,
          onTap: (_, latLng) {
            _superclusterController.add(
              Marker(
                anchorPos: AnchorPos.align(AnchorAlign.center),
                height: 30,
                width: 30,
                point: latLng,
                builder: (ctx) => const Icon(Icons.pin_drop_outlined),
              ),
            );
          }, // Hide popup when the map is tapped.
        ),
        children: <Widget>[
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
          ),
          SuperclusterLayer.mutable(
            initialMarkers: markers,
            controller: _superclusterController,
            onMarkerTap: (marker) {
              _superclusterController.remove(marker);
            },
            rotate: true,
            clusterWidgetSize: const Size(40, 40),
            anchor: AnchorPos.align(AnchorAlign.center),
            clusterZoomAnimation: const AnimationOptions.animate(
              curve: Curves.linear,
              velocity: 1,
            ),
            calculateAggregatedClusterData: true,
            builder: (context, position, markerCount, extraClusterData) {
              return Container(
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20.0),
                    color: Colors.blue),
                child: Center(
                  child: Text(
                    markerCount.toString(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
