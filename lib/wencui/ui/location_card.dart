import 'package:flutter/material.dart';

import '../../ui/design.dart';
import '../atlas.dart';
import '../place.dart';
import 'floor_image.dart';

/// A room's location and map entry form a single action in course details.
class WencuiLocationCard extends StatelessWidget {
  const WencuiLocationCard({
    super.key,
    required this.place,
    required this.onTap,
  });

  final WencuiPlace place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final floor = place.floor ?? place.wing.firstFloor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: AppCorners.control,
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  width: 76,
                  height: 76,
                  child: ExcludeSemantics(
                    child: ClipRRect(
                      borderRadius: AppCorners.compact,
                      child: FutureBuilder<WencuiAtlas>(
                        future: WencuiAtlas.load(),
                        builder: (context, snapshot) {
                          final room = snapshot.data?.room(place.label);
                          final bounds =
                              room?.bounds ??
                              snapshot.data?.wingBounds(floor, place.wing);
                          return _RoomPreview(
                            floor: floor,
                            bounds: bounds,
                            room: room,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '文萃楼 ${place.label}',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${place.wing.name} · $floor层',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '查看教室位置',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomPreview extends StatelessWidget {
  const _RoomPreview({required this.floor, this.bounds, this.room});

  final int floor;
  final Rect? bounds;
  final WencuiFeature? room;

  @override
  Widget build(BuildContext context) {
    final crop = (bounds ?? const Rect.fromLTWH(0, 0, 1, 1)).inflate(.025);
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: crop.width * wencuiFloorSize.width,
        height: crop.height * wencuiFloorSize.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -crop.left * wencuiFloorSize.width,
              top: -crop.top * wencuiFloorSize.height,
              width: wencuiFloorSize.width,
              height: wencuiFloorSize.height,
              child: Stack(
                children: [
                  WencuiFloorImage(floor: floor),
                  if (room != null)
                    Positioned.fromRect(
                      rect: Rect.fromLTRB(
                        room!.bounds.left * wencuiFloorSize.width,
                        room!.bounds.top * wencuiFloorSize.height,
                        room!.bounds.right * wencuiFloorSize.width,
                        room!.bounds.bottom * wencuiFloorSize.height,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary
                              .withValues(alpha: .25),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
