import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class ThemeConfig {
  static final instance = ThemeConfig();
  static const String darkModeScript = r'''(() => {
    if (window.__nexusDarkMode) return; window.__nexusDarkMode = true;
    const id='__nexus_dark_mode';
    const apply=()=>{ let el=document.getElementById(id); if(!el){el=document.createElement('style');el.id=id;document.documentElement.appendChild(el);} el.textContent='html{background:#121212!important;}body{background:#121212!important;color:#e8e8e8!important;} body a{color:#8ab4f8!important;} img,video{filter:none!important;}'; };
    apply();
  })();''';
  int bgBase = 0xFF1E1E1E, bgSurface = 0xFF2E3033, bgRaised = 0xFF3A3D40, accent = 0xFFFFB800, success = 0xFF00FF66, danger = 0xFFFF3B3B, text = 0xFFFFFFFF, muted = 0xFFA0A0A0, border = 0xFF3F4245;
  double radius = 18, spacing = 4;
  String displayFont = 'Chakra Petch', uiFont = 'Inter', monoFont = 'JetBrains Mono';
  bool autoDarkWeb = true;
  String _hex(int v)=>'#${v.toRadixString(16).padLeft(8,'0')}';
  int _color(dynamic v,int fallback){ if(v is num)return v.toInt(); if(v is String){ final x=v.replaceAll('#',''); return int.tryParse(x.length==6?'FF$x':x,radix:16)??fallback;} return fallback; }
  Map<String,dynamic> toJson()=>{'colors':{'bgBase':_hex(bgBase),'bgSurface':_hex(bgSurface),'bgRaised':_hex(bgRaised),'accent':_hex(accent),'success':_hex(success),'danger':_hex(danger),'text':_hex(text),'muted':_hex(muted),'border':_hex(border)},'radius':radius,'spacing':spacing,'fonts':{'display':displayFont,'ui':uiFont,'mono':monoFont},'autoDarkWeb':autoDarkWeb};
  void apply(Map<String,dynamic> j){ final c=Map<String,dynamic>.from(j['colors']??{}); bgBase=_color(c['bgBase'],bgBase); bgSurface=_color(c['bgSurface'],bgSurface); bgRaised=_color(c['bgRaised'],bgRaised); accent=_color(c['accent'],accent); success=_color(c['success'],success); danger=_color(c['danger'],danger); text=_color(c['text'],text); muted=_color(c['muted'],muted); border=_color(c['border'],border); radius=(j['radius']??radius).toDouble(); spacing=(j['spacing']??spacing).toDouble(); final f=Map<String,dynamic>.from(j['fonts']??{}); displayFont=f['display']??displayFont; uiFont=f['ui']??uiFont; monoFont=f['mono']??monoFont; autoDarkWeb=j['autoDarkWeb']??autoDarkWeb; }
  ThemeData materialTheme()=>ThemeData(useMaterial3:true, brightness:Brightness.dark, scaffoldBackgroundColor:Color(bgBase), colorScheme:ColorScheme.fromSeed(seedColor:Color(accent),brightness:Brightness.dark,primary:Color(accent),surface:Color(bgSurface),onSurface:Color(text),error:Color(danger)), textTheme:TextTheme(bodyMedium:TextStyle(color:Color(text),fontFamily:uiFont),bodySmall:TextStyle(color:Color(muted),fontFamily:uiFont),titleMedium:TextStyle(color:Color(text),fontFamily:displayFont)), dividerColor:Color(border));
  Future<void> load() async { try { final d=await getApplicationDocumentsDirectory(); final f=File('${d.path}/theme.json'); if(await f.exists()) apply(jsonDecode(await f.readAsString())); }catch(_){} }
  Future<void> save() async { try { final d=await getApplicationDocumentsDirectory(); await File('${d.path}/theme.json').writeAsString(const JsonEncoder.withIndent('  ').convert(toJson())); }catch(_){} }
}
