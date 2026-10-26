import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

const sakura = Color(0xFFFF5C8A);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  runApp(const OtakuEventsApp());
}

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {}
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static int _nid(OtakuEvent e) => e.id.hashCode & 0x7fffffff;

  static Future<void> cancel(OtakuEvent e) => _plugin.cancel(_nid(e));

  static Future<void> schedule(OtakuEvent e) async {
    await cancel(e);
    final minutes = e.reminderMinutes;
    if (minutes == null) return;
    final at = e.dateTime.subtract(Duration(minutes: minutes));
    if (!at.isAfter(DateTime.now())) return;
    final body = [
      'Starts at ${DateFormat.jm().format(e.dateTime)}',
      if (e.location.isNotEmpty) e.location,
    ].join(' - ');
    await _plugin.zonedSchedule(
      _nid(e),
      e.name,
      body,
      tz.TZDateTime.from(at, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'event_reminders',
          'Event reminders',
          channelDescription: 'Reminders before your events start',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}

String reminderLabel(int? m) {
  switch (m) {
    case null:
      return 'No reminder';
    case 0:
      return 'At event time';
    case 30:
      return '30 minutes before';
    case 60:
      return '1 hour before';
    case 1440:
      return '1 day before';
    default:
      return '$m minutes before';
  }
}

class OtakuEventsApp extends StatelessWidget {
  const OtakuEventsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: sakura,
      brightness: Brightness.dark,
    ).copyWith(surface: Colors.black, primary: sakura);
    return MaterialApp(
      title: 'Otaku Events',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF141418),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const EventListScreen(),
    );
  }
}

Uri? toWebUri(String raw) {
  final t = raw.trim();
  if (t.isEmpty || t.contains(' ')) return null;
  final uri = Uri.tryParse(t.startsWith('http') ? t : 'https://$t');
  if (uri == null || !uri.host.contains('.')) return null;
  return uri;
}

Future<void> openLink(BuildContext context, String raw) async {
  final uri = toWebUri(raw);
  final ok = uri != null &&
      await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Could not open link')));
  }
}

enum EventCategory { anime, cosplay, gaming, concert, movie }

extension EventCategoryX on EventCategory {
  String get label => switch (this) {
        EventCategory.anime => 'Anime',
        EventCategory.cosplay => 'Cosplay',
        EventCategory.gaming => 'Gaming',
        EventCategory.concert => 'Concert',
        EventCategory.movie => 'Movie',
      };

  IconData get icon => switch (this) {
        EventCategory.anime => Icons.auto_awesome,
        EventCategory.cosplay => Icons.checkroom,
        EventCategory.gaming => Icons.sports_esports,
        EventCategory.concert => Icons.music_note,
        EventCategory.movie => Icons.movie_outlined,
      };

  Color get color => switch (this) {
        EventCategory.anime => const Color(0xFFFF5C8A),
        EventCategory.cosplay => const Color(0xFFB388FF),
        EventCategory.gaming => const Color(0xFF4DD0E1),
        EventCategory.concert => const Color(0xFFFFB74D),
        EventCategory.movie => const Color(0xFF81C784),
      };
}

class _Tag extends StatelessWidget {
  const _Tag(this.icon, this.label, this.color);
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      );
}

Widget eventTags(OtakuEvent e, {WrapAlignment alignment = WrapAlignment.start}) =>
    Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: alignment,
      children: [
        _Tag(e.category.icon, e.category.label, e.category.color),
        _Tag(e.isPaid ? Icons.payments_outlined : Icons.money_off,
            e.paidLabel,
            e.isPaid ? Colors.amber : Colors.greenAccent),
        _Tag(e.isOutdoor ? Icons.park_outlined : Icons.home_outlined,
            e.isOutdoor ? 'Outdoors' : 'Indoors', Colors.lightBlueAccent),
      ],
    );

class OtakuEvent {
  OtakuEvent({
    required this.id,
    required this.name,
    required this.dateTime,
    required this.location,
    required this.description,
    this.logoPath,
    this.reminderMinutes,
    this.category = EventCategory.anime,
    this.isPaid = false,
    this.isOutdoor = false,
    this.price = '',
    this.website = '',
    this.announcement = '',
  });

  final String id;
  String name;
  DateTime dateTime;
  String location;
  String description;
  String? logoPath;
  int? reminderMinutes;
  EventCategory category;
  bool isPaid;
  bool isOutdoor;
  String price;
  String website;
  String announcement;

  String get paidLabel =>
      isPaid ? (price.isEmpty ? 'Paid' : 'Paid: $price') : 'Free';

  String get summary =>
      '${category.label} - $paidLabel - ${isOutdoor ? 'Outdoors' : 'Indoors'}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'dateTime': dateTime.toIso8601String(),
        'location': location,
        'description': description,
        'logoPath': logoPath,
        'reminderMinutes': reminderMinutes,
        'category': category.name,
        'isPaid': isPaid,
        'isOutdoor': isOutdoor,
        'price': price,
        'website': website,
        'announcement': announcement,
      };

  factory OtakuEvent.fromJson(Map<String, dynamic> j) => OtakuEvent(
        id: j['id'],
        name: j['name'],
        dateTime: DateTime.parse(j['dateTime']),
        location: j['location'] ?? '',
        description: j['description'] ?? '',
        logoPath: j['logoPath'],
        reminderMinutes: j['reminderMinutes'],
        category: EventCategory.values.firstWhere(
            (c) => c.name == j['category'],
            orElse: () => EventCategory.anime),
        isPaid: j['isPaid'] ?? false,
        isOutdoor: j['isOutdoor'] ?? false,
        price: j['price'] ?? '',
        website: j['website'] ?? '',
        announcement: j['announcement'] ?? '',
      );
}

class EventStore {
  static const _key = 'events_v1';

  static Future<List<OtakuEvent>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List)
        .map((e) => OtakuEvent.fromJson(e as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return list;
  }

  static Future<void> save(List<OtakuEvent> events) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(events.map((e) => e.toJson()).toList()));
  }
}

class EventListScreen extends StatefulWidget {
  const EventListScreen({super.key});

  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen> {
  List<OtakuEvent> _events = [];
  bool _loading = true;
  EventCategory? _filter;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final events = await EventStore.load();
    if (!mounted) return;
    setState(() {
      _events = events;
      _loading = false;
    });
  }

  Future<void> _open([OtakuEvent? event]) async {
    final saved = await Navigator.of(context).push<OtakuEvent>(
      MaterialPageRoute(builder: (_) => EventFormScreen(event: event)),
    );
    if (saved == null) return;
    final i = _events.indexWhere((e) => e.id == saved.id);
    if (i >= 0) {
      _events[i] = saved;
    } else {
      _events.add(saved);
    }
    _events.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    await EventStore.save(_events);
    await NotificationService.schedule(saved);
    setState(() {});
  }

  Future<void> _view(OtakuEvent e) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => EventDetailScreen(event: e)),
    );
    if (result == 'edit') await _open(e);
  }

  Future<void> _delete(OtakuEvent e) async {
    setState(() => _events.removeWhere((x) => x.id == e.id));
    await NotificationService.cancel(e);
    await EventStore.save(_events);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final visible = _filter == null
        ? _events
        : _events.where((e) => e.category == _filter).toList();
    final upcoming = visible.where((e) => !e.dateTime.isBefore(now)).toList();
    final past = visible.where((e) => e.dateTime.isBefore(now)).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Otaku Events',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 26)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('Add event'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
              ? const _EmptyState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    _filterBar(),
                    if (visible.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No events in this category yet.',
                            textAlign: TextAlign.center),
                      ),
                    if (upcoming.isNotEmpty) _header('Upcoming'),
                    ...upcoming.map(_card),
                    if (past.isNotEmpty) _header('Past'),
                    ...past.map((e) => Opacity(opacity: .5, child: _card(e))),
                  ],
                ),
    );
  }

  Widget _filterBar() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All'),
              selected: _filter == null,
              selectedColor: sakura,
              labelStyle:
                  TextStyle(color: _filter == null ? Colors.black : null),
              showCheckmark: false,
              onSelected: (_) => setState(() => _filter = null),
            ),
          ),
          ...EventCategory.values.map((c) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(c.icon,
                      size: 18, color: _filter == c ? Colors.black : c.color),
                  label: Text(c.label),
                  selected: _filter == c,
                  selectedColor: c.color,
                  labelStyle:
                      TextStyle(color: _filter == c ? Colors.black : null),
                  showCheckmark: false,
                  onSelected: (_) =>
                      setState(() => _filter = _filter == c ? null : c),
                ),
              )),
        ]),
      );

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: sakura)),
      );

  Widget _card(OtakuEvent e) => Dismissible(
        key: ValueKey(e.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.red.shade900,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.delete_outline),
        ),
        onDismissed: (_) => _delete(e),
        child: _EventCard(event: e, onTap: () => _view(e)),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.festival_outlined, size: 64, color: sakura),
              SizedBox(height: 16),
              Text('No events yet',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              Text(
                'Add a convention, screening or meetup with its logo, date, time and location.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onTap});
  final OtakuEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = event.dateTime;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141418),
        borderRadius: BorderRadius.circular(18),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Logo(path: event.logoPath, size: 72),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    eventTags(event),
                    const SizedBox(height: 6),
                    _line(Icons.event,
                        '${DateFormat('EEE, d MMM y').format(d)} at ${DateFormat.jm().format(d)}'),
                    if (event.location.isNotEmpty)
                      _line(Icons.place_outlined, event.location),
                    if (event.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(event.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(IconData i, String t) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(children: [
          Icon(i, size: 15, color: sakura),
          const SizedBox(width: 6),
          Expanded(
              child: Text(t,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13))),
        ]),
      );
}

class _Logo extends StatelessWidget {
  const _Logo({required this.path, required this.size});
  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasFile = path != null && File(path!).existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFF26202A),
        child: hasFile
            ? Image.file(File(path!), fit: BoxFit.cover)
            : Icon(Icons.add_photo_alternate_outlined,
                size: size * .4, color: Colors.white54),
      ),
    );
  }
}

class EventFormScreen extends StatefulWidget {
  const EventFormScreen({super.key, this.event});
  final OtakuEvent? event;

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _location;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _website;
  late final TextEditingController _announcement;
  late DateTime _date;
  late TimeOfDay _time;
  String? _logoPath;
  int? _reminder;
  EventCategory _category = EventCategory.anime;
  bool _paid = false;
  bool _outdoor = false;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    final base = e?.dateTime ?? DateTime.now().add(const Duration(days: 1));
    _name = TextEditingController(text: e?.name ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _price = TextEditingController(text: e?.price ?? '');
    _website = TextEditingController(text: e?.website ?? '');
    _announcement = TextEditingController(text: e?.announcement ?? '');
    _date = DateTime(base.year, base.month, base.day);
    _time = TimeOfDay(hour: base.hour, minute: base.minute);
    _logoPath = e?.logoPath;
    _reminder = e?.reminderMinutes;
    _category = e?.category ?? EventCategory.anime;
    _paid = e?.isPaid ?? false;
    _outdoor = e?.isOutdoor ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _description.dispose();
    _price.dispose();
    _website.dispose();
    _announcement.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (picked == null) return;
    // Copy into app storage so the logo survives gallery changes.
    final dir = await getApplicationDocumentsDirectory();
    final dest =
        '${dir.path}/logo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(picked.path).copy(dest);
    setState(() => _logoPath = dest);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(OtakuEvent(
      id: widget.event?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      dateTime: DateTime(
          _date.year, _date.month, _date.day, _time.hour, _time.minute),
      location: _location.text.trim(),
      description: _description.text.trim(),
      logoPath: _logoPath,
      reminderMinutes: _reminder,
      category: _category,
      isPaid: _paid,
      isOutdoor: _outdoor,
      price: _paid ? _price.text.trim() : '',
      website: _website.text.trim(),
      announcement: _announcement.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.event == null ? 'New event' : 'Edit event')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickLogo,
                child: Column(children: [
                  _Logo(path: _logoPath, size: 120),
                  const SizedBox(height: 8),
                  Text(_logoPath == null ? 'Add logo' : 'Change logo',
                      style: const TextStyle(color: sakura)),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Event name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter an event name' : null,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: EventCategory.values
                  .map((c) => ChoiceChip(
                        avatar: Icon(c.icon,
                            size: 18,
                            color: _category == c ? Colors.black : c.color),
                        label: Text(c.label),
                        selected: _category == c,
                        selectedColor: c.color,
                        labelStyle: TextStyle(
                            color: _category == c ? Colors.black : null),
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _category = c),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: _PickerTile(
                  icon: Icons.event,
                  label: DateFormat('d MMM y').format(_date),
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PickerTile(
                  icon: Icons.schedule,
                  label: _time.format(context),
                  onTap: _pickTime,
                ),
              ),
            ]),
            const SizedBox(height: 14),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(
                labelText: 'Location',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _website,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Official website',
                prefixIcon: Icon(Icons.language),
              ),
              validator: (v) => (v == null ||
                      v.trim().isEmpty ||
                      toWebUri(v) != null)
                  ? null
                  : 'Enter a valid link, e.g. example.com',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _announcement,
              decoration: const InputDecoration(
                labelText: 'Announcement source (link or post name)',
                prefixIcon: Icon(Icons.campaign_outlined),
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: false,
                    label: Text('Free'),
                    icon: Icon(Icons.money_off)),
                ButtonSegment(
                    value: true,
                    label: Text('Paid'),
                    icon: Icon(Icons.payments_outlined)),
              ],
              selected: {_paid},
              onSelectionChanged: (s) => setState(() => _paid = s.first),
            ),
            if (_paid) ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: _price,
                decoration: const InputDecoration(
                  labelText: 'Ticket price (e.g. \$25 or ¥3000)',
                  prefixIcon: Icon(Icons.confirmation_number_outlined),
                ),
              ),
            ],
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: false,
                    label: Text('Indoors'),
                    icon: Icon(Icons.home_outlined)),
                ButtonSegment(
                    value: true,
                    label: Text('Outdoors'),
                    icon: Icon(Icons.park_outlined)),
              ],
              selected: {_outdoor},
              onSelectionChanged: (s) => setState(() => _outdoor = s.first),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int?>(
              value: _reminder,
              decoration: const InputDecoration(
                labelText: 'Reminder',
                prefixIcon: Icon(Icons.notifications_none),
              ),
              items: [null, 0, 30, 60, 1440]
                  .map((m) => DropdownMenuItem<int?>(
                      value: m, child: Text(reminderLabel(m))))
                  .toList(),
              onChanged: (v) => setState(() => _reminder = v),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _description,
              minLines: 4,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: const Text('Save event'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          decoration: BoxDecoration(
            color: const Color(0xFF141418),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Icon(icon, size: 20, color: sakura),
            const SizedBox(width: 10),
            Expanded(child: Text(label)),
          ]),
        ),
      );
}


class EventDetailScreen extends StatelessWidget {
  const EventDetailScreen({super.key, required this.event});
  final OtakuEvent event;

  String get _when =>
      '${DateFormat('EEEE, d MMMM y').format(event.dateTime)} at ${DateFormat.jm().format(event.dateTime)}';

  Future<void> _share() async {
    final text = StringBuffer(event.name)
      ..writeln(event.summary)
      ..writeln()
      ..writeln(_when);
    if (event.location.isNotEmpty) text.writeln(event.location);
    if (event.website.isNotEmpty) text.writeln(event.website);
    if (event.description.isNotEmpty) {
      text
        ..writeln()
        ..writeln(event.description);
    }
    final logo = event.logoPath;
    if (logo != null && File(logo).existsSync()) {
      await Share.shareXFiles([XFile(logo)], text: text.toString());
    } else {
      await Share.share(text.toString());
    }
  }

  Future<void> _openMaps(BuildContext context) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(event.location)}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Maps')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
              tooltip: 'Share',
              onPressed: _share,
              icon: const Icon(Icons.ios_share)),
          IconButton(
              tooltip: 'Edit',
              onPressed: () => Navigator.of(context).pop('edit'),
              icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: _Logo(path: event.logoPath, size: 160)),
          const SizedBox(height: 20),
          Text(event.name,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          eventTags(event, alignment: WrapAlignment.center),
          const SizedBox(height: 16),
          _row(Icons.event, _when),
          if (event.reminderMinutes != null)
            _row(Icons.notifications_none, reminderLabel(event.reminderMinutes)),
          if (event.location.isNotEmpty) ...[
            _row(Icons.place_outlined, event.location),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _openMaps(context),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Open in Maps'),
            ),
          ],
          if (event.website.isNotEmpty) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => openLink(context, event.website),
              icon: const Icon(Icons.language),
              label: const Text('Official website'),
            ),
          ],
          if (event.announcement.isNotEmpty) ...[
            const SizedBox(height: 8),
            toWebUri(event.announcement) != null
                ? OutlinedButton.icon(
                    onPressed: () => openLink(context, event.announcement),
                    icon: const Icon(Icons.campaign_outlined),
                    label: const Text('Official announcement'),
                  )
                : _row(Icons.campaign_outlined,
                    'Announced via ${event.announcement}'),
          ],
          if (event.description.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(event.description,
                style: const TextStyle(fontSize: 15, height: 1.5)),
          ],
        ],
      ),
    );
  }

  Widget _row(IconData i, String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(i, size: 20, color: sakura),
          const SizedBox(width: 10),
          Expanded(child: Text(t, style: const TextStyle(fontSize: 15))),
        ]),
      );
}