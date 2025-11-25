import 'package:flutter/material.dart';
import 'package:stretchable_image/stretchable_image.dart';

void main() {
  runApp(const StretchableImageExampleApp());
}

class StretchableImageExampleApp extends StatelessWidget {
  const StretchableImageExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'StretchableImage Example',
      home: StretchableImageDemoPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class StretchableImageDemoPage extends StatelessWidget {
  const StretchableImageDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    const double height = 40;

    return Scaffold(
      appBar: AppBar(
        title: const Text('StretchableImage Demo'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text(
                'border.png as background. '
                    'Show how the image behaves with different widths.',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24),
              Text('Narrow (compressed, middle area may be clipped)'),
              SizedBox(height: 8),
              StretchableImage(
                image: AssetImage('images/border.png'),
                size: Size(40, height),
              ),
              SizedBox(height: 24),
              Text('Normal width (close to original aspect)'),
              SizedBox(height: 8),
              StretchableImage(
                image: AssetImage('images/border.png'),
                size: Size(62, height),
              ),
              SizedBox(height: 24),
              Text('Wide (middle area is stretched)'),
              SizedBox(height: 8),
              StretchableImage(
                image: AssetImage('images/border.png'),
                size: Size(120, height),
              ),
              SizedBox(height: 24),
              Text('Extra wide (strong stretch in the middle)'),
              SizedBox(height: 8),
              StretchableImage(
                image: AssetImage('images/border.png'),
                size: Size(360, height),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


