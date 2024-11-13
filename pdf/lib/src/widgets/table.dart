import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../pdf.dart';
import '../../widgets.dart';

@immutable
class TableRow {
  const TableRow({
    required this.children,
    this.repeat = false,
    this.verticalAlignment,
    this.decoration,
  });

  final List<Widget> children;
  final bool repeat;
  final BoxDecoration? decoration;
  final TableCellVerticalAlignment? verticalAlignment;
}

enum TableCellVerticalAlignment { bottom, middle, top, full }

enum TableWidth { min, max }

class TableBorder extends Border {
  const TableBorder({
    BorderSide left = BorderSide.none,
    BorderSide top = BorderSide.none,
    BorderSide right = BorderSide.none,
    BorderSide bottom = BorderSide.none,
    this.horizontalInside = BorderSide.none,
    this.verticalInside = BorderSide.none,
  }) : super(top: top, bottom: bottom, left: left, right: right);

  final BorderSide horizontalInside;
  final BorderSide verticalInside;

  factory TableBorder.all({
    BorderSide side = const BorderSide(),
  }) {
    return TableBorder(
      left: side,
      top: side,
      right: side,
      bottom: side,
      horizontalInside: side,
      verticalInside: side,
    );
  }

  void paintTable(Context context, PdfRect box,
      [List<double?>? widths, List<double>? heights]) {
    super.paint(context, box);

    if (verticalInside.style.paint) {
      verticalInside.style.setStyle(context);
      var offset = box.x;
      for (final width in widths!.sublist(0, widths.length - 1)) {
        offset += width!;
        context.canvas.moveTo(offset, box.y);
        context.canvas.lineTo(offset, box.top);
      }
      context.canvas.setStrokeColor(verticalInside.color);
      context.canvas.setLineWidth(verticalInside.width);
      context.canvas.strokePath();
      verticalInside.style.unsetStyle(context);
    }

    if (horizontalInside.style.paint) {
      horizontalInside.style.setStyle(context);
      var offset = box.top;
      for (final height in heights!.sublist(0, heights.length - 1)) {
        offset -= height;
        context.canvas.moveTo(box.x, offset);
        context.canvas.lineTo(box.right, offset);
      }
      context.canvas.setStrokeColor(horizontalInside.color);
      context.canvas.setLineWidth(horizontalInside.width);
      context.canvas.strokePath();
      horizontalInside.style.unsetStyle(context);
    }
  }
}

class TableContext extends WidgetContext {
  int firstLine = 0;
  int lastLine = 0;
  double? previousCalculatedWidth;
  List<double> widths = <double>[];

  @override
  void apply(TableContext other) {
    firstLine = other.firstLine;
    lastLine = other.lastLine;
    previousCalculatedWidth = other.previousCalculatedWidth;
    widths = List<double>.from(other.widths);
  }

  @override
  WidgetContext clone() {
    return TableContext()..apply(this);
  }
}

class ColumnLayout {
  ColumnLayout(this.width, this.flex);

  final double width;
  final double flex;
}

abstract class TableColumnWidth {
  const TableColumnWidth();

  ColumnLayout layout(
      Widget child, Context context, BoxConstraints constraints);
}

class FixedColumnWidth extends TableColumnWidth {
  const FixedColumnWidth(this.width);

  final double width;

  @override
  ColumnLayout layout(
      Widget child, Context context, BoxConstraints? constraints) {
    return ColumnLayout(width, 0);
  }
}

class Table extends Widget with SpanningWidget {
  Table({
    this.children = const <TableRow>[],
    this.border,
    this.defaultVerticalAlignment = TableCellVerticalAlignment.top,
    this.columnWidths,
    this.defaultColumnWidth = const FixedColumnWidth(50.0),
    this.tableWidth = TableWidth.max,
  }) : super();

  final List<TableRow> children;
  final TableBorder? border;
  final TableCellVerticalAlignment defaultVerticalAlignment;
  final TableWidth tableWidth;
  final List<double> _widths = <double>[];
  final List<double> _heights = <double>[];
  final TableContext _context = TableContext();
  final TableColumnWidth defaultColumnWidth;
  final Map<int, TableColumnWidth>? columnWidths;

  @override
  WidgetContext saveContext() {
    return _context;
  }

  @override
  void restoreContext(TableContext context) {
    _context.apply(context);
    _context.firstLine = _context.lastLine;
  }

  @override
  bool get canSpan => true;

  @override
  bool get hasMoreWidgets => _context.lastLine < children.length;

  double _calculateTotalWidth(Context context, BoxConstraints constraints) {
    if (_context.previousCalculatedWidth != null &&
        _context.widths.isNotEmpty) {
      _widths.clear();
      _widths.addAll(_context.widths);
      return _context.previousCalculatedWidth!;
    }

    final flex = <double>[];
    for (final row in children) {
      for (final entry in row.children.asMap().entries) {
        final index = entry.key;
        final child = entry.value;
        final columnWidth = columnWidths?[index] ?? defaultColumnWidth;
        final columnLayout = columnWidth.layout(child, context, constraints);

        if (index >= flex.length) {
          flex.add(columnLayout.flex);
          _widths.add(columnLayout.width);
        } else {
          if (columnLayout.flex > 0) {
            flex[index] = math.max(flex[index], columnLayout.flex);
          }
          _widths[index] = math.max(_widths[index], columnLayout.width);
        }
      }
    }

    if (_widths.isEmpty) {
      return 0.0;
    }

    final maxWidth = _widths.fold(0.0, (sum, element) => sum + element);

    if (constraints.hasBoundedWidth) {
      final totalFlex = flex.reduce((a, b) => a + b);
      var flexSpace = 0.0;
      for (var n = 0; n < _widths.length; n++) {
        if (flex[n] == 0.0) {
          final newWidth = _widths[n] / maxWidth * constraints.maxWidth;
          _widths[n] = newWidth;
          flexSpace += newWidth;
        }
      }
      final spacePerFlex = totalFlex > 0.0
          ? ((constraints.maxWidth - flexSpace) / totalFlex)
          : double.nan;

      for (var n = 0; n < _widths.length; n++) {
        if (flex[n] > 0.0) {
          _widths[n] = spacePerFlex * flex[n];
        }
      }
    }

    final totalWidth = _widths.fold(0.0, (sum, element) => sum + element);
    _context.previousCalculatedWidth = totalWidth;
    _context.widths.clear();
    _context.widths.addAll(_widths);
    return totalWidth;
  }

  @override
  void layout(Context context, BoxConstraints constraints,
      {bool parentUsesSize = false}) {
    _widths.clear();
    _heights.clear();

    final totalWidth = _calculateTotalWidth(context, constraints);

    if (totalWidth == 0) {
      box = PdfRect.fromPoints(PdfPoint.zero, constraints.smallest);
      return;
    }

    double totalHeight = 0.0;
    int index = 0;

    for (final row in children) {
      if (index++ < _context.firstLine && !row.repeat) continue;

      double x = 0.0;
      double lineHeight = 0.0;
      final rowChildren = row.children;
      final numChildren = rowChildren.length;

      for (int n = 0; n < numChildren; n++) {
        final child = rowChildren[n];
        final width = _widths[n];

        final childConstraints = BoxConstraints.tightFor(width: width);
        child.layout(context, childConstraints);

        final box = child.box;
        if (box != null) {
          child.box = PdfRect(x, totalHeight, box.width, box.height);
          x += width;
          lineHeight = math.max(lineHeight, box.height);
        }
      }

      final align = row.verticalAlignment ?? defaultVerticalAlignment;
      if (align == TableCellVerticalAlignment.full) {
        x = 0;
        for (int n = 0; n < numChildren; n++) {
          final child = rowChildren[n];
          final width = _widths[n];
          final childConstraints =
              BoxConstraints.tightFor(width: width, height: lineHeight);
          child.layout(context, childConstraints);

          final box = child.box;
          if (box != null) {
            child.box = PdfRect(x, totalHeight, box.width, box.height);
            x += width;
          }
        }
      }

      if (totalHeight + lineHeight > constraints.maxHeight) {
        index--;
        break;
      }

      totalHeight += lineHeight;
      _heights.add(lineHeight);
    }
    _context.lastLine = index;
    box = PdfRect(0, 0, totalWidth, totalHeight);
  }

  @override
  void paint(Context context) {
    super.paint(context);

    if (_context.lastLine == 0) {
      return;
    }

    final mat = Matrix4.identity();
    mat.translate(box!.x, box!.y);
    context.canvas
      ..saveContext()
      ..setTransform(mat);

    var index = 0;
    for (final row in children) {
      if (index++ < _context.firstLine && !row.repeat) {
        continue;
      }

      if (row.decoration != null) {
        var y = double.infinity;
        var h = 0.0;
        for (final child in row.children) {
          y = math.min(y, child.box!.y);
          h = math.max(h, child.box!.height);
        }
        row.decoration!.paint(
          context,
          PdfRect(0, y, box!.width, h),
          PaintPhase.background,
        );
      }

      for (final child in row.children) {
        context.canvas
          ..saveContext()
          ..drawRect(
              child.box!.x, child.box!.y, child.box!.width, child.box!.height)
          ..clipPath();
        child.paint(context);
        context.canvas.restoreContext();
      }
      if (index >= _context.lastLine) {
        break;
      }
    }

    index = 0;
    for (final row in children) {
      if (index++ < _context.firstLine && !row.repeat) {
        continue;
      }

      if (row.decoration != null) {
        var y = double.infinity;
        var h = 0.0;
        for (final child in row.children) {
          y = math.min(y, child.box!.y);
          h = math.max(h, child.box!.height);
        }
        row.decoration!.paint(
          context,
          PdfRect(0, y, box!.width, h),
          PaintPhase.foreground,
        );
      }

      if (index >= _context.lastLine) {
        break;
      }
    }

    context.canvas.restoreContext();

    if (border != null) {
      border!.paintTable(context, box!, _widths, _heights);
    }
  }
}
