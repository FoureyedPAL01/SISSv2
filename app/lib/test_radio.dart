import 'package:flutter/material.dart';

void main() {
  runApp(
    MaterialApp(
      home: Scaffold(
        body: RadioGroup<String>(
          groupValue: 'a',
          onChanged: (String? value) {},
          child: Column(
            children: [
              RadioListTile<String>(title: Text('A'), value: 'a'),
            ],
          ),
        ),
      ),
    ),
  );
}
