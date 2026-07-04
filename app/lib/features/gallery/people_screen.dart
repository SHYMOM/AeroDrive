import 'package:flutter/material.dart';
import '../faces/faces_screen.dart';

class PeopleScreenContent extends StatelessWidget {
  const PeopleScreenContent({super.key});

  @override
  Widget build(BuildContext context) {
    // Instead of mock data, we simply embed the actual ML-driven FacesScreen
    // Since FacesScreen has its own Scaffold/AppBar, we might just want to 
    // extract its body or let it handle its own display. But for MediaScreen integration,
    // embedding the FacesScreen directly works.
    return const FacesScreen();
  }
}
