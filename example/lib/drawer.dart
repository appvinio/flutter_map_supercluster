import 'package:flutter/material.dart';
import 'package:flutter_map_supercluster_example/immutable_clustering_page.dart';
import 'package:flutter_map_supercluster_example/mutable_clustering_page.dart';

Widget _buildMenuItem(
    BuildContext context, Widget title, String routeName, String currentRoute) {
  var isSelected = routeName == currentRoute;

  return ListTile(
    title: title,
    selected: isSelected,
    onTap: () {
      if (isSelected) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacementNamed(context, routeName);
      }
    },
  );
}

Drawer buildDrawer(BuildContext context, String currentRoute) {
  return Drawer(
    child: ListView(
      children: <Widget>[
        const DrawerHeader(
          child: Center(
            child: Text('Flutter Map Supercluster Examples'),
          ),
        ),
        _buildMenuItem(
          context,
          const Text('Clustering (mutable)'),
          MutableClusteringPage.route,
          currentRoute,
        ),
        _buildMenuItem(
          context,
          const Text('Clustering Many Markers (immutable)'),
          ClusteringManyMarkersPage.route,
          currentRoute,
        ),
      ],
    ),
  );
}
