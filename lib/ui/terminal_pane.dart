import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/nexus_theme.dart';

class TerminalPane extends StatefulWidget { const TerminalPane({super.key, required this.initialText, required this.onTextChanged}); final String initialText; final ValueChanged<String> onTextChanged; @override State<TerminalPane> createState()=>_TerminalPaneState(); }
class _TerminalPaneState extends State<TerminalPane>{ late final TextEditingController input; late String output; bool running=false;
 @override void initState(){super.initState(); output=widget.initialText; input=TextEditingController();}
 @override void dispose(){input.dispose();super.dispose();}
 Future<void> run() async { final cmd=input.text.trim(); if(cmd.isEmpty)return; input.clear(); setState(()=>running=true); output+='\n\$ $cmd\n'; try { final p=await Process.start('/system/bin/sh',['-c',cmd],runInShell:false); final out=StringBuffer(); final err=StringBuffer(); p.stdout.transform(const SystemEncoding().decoder).listen(out.write); p.stderr.transform(const SystemEncoding().decoder).listen(err.write); final code=await p.exitCode; output+=out.toString(); if(err.isNotEmpty)output+=err.toString(); output+='\n[exit $code]\n'; } catch(e){output+='Terminal error: $e\n';} if(mounted){setState(()=>running=false);widget.onTextChanged(output);}}
 @override Widget build(BuildContext context)=>Container(color:const Color(0xFF111111),padding:const EdgeInsets.all(10),child:Column(children:[
   // Führt echte Shell-Befehle im Sandbox der App aus (keine Root-Rechte,
   // aber echte Codeausführung mit den eigenen Rechten der App). Bewusst
   // als dauerhaft sichtbarer Hinweis statt einmaligem Dialog, der
   // weggeklickt und vergessen wird — besonders wichtig, falls die App
   // mal an jemand anderen weitergegeben wird.
   Container(
     width: double.infinity,
     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
     margin: const EdgeInsets.only(bottom: 8),
     decoration: BoxDecoration(color: NexusColors.accentDanger.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
     child: const Text('⚠ Führt echte Shell-Befehle aus (App-Sandbox, kein Root). Nur für dich selbst.',
       style: TextStyle(fontSize: 10, color: NexusColors.accentDanger)),
   ),
   Expanded(child:SingleChildScrollView(reverse:true,child:Text(output,style:const TextStyle(fontFamily:'monospace',fontSize:12,color:Colors.white)))),const SizedBox(height:8),Row(children:[const Text('\$ ',style:TextStyle(color:NexusColors.accentPrimary,fontFamily:'monospace')),Expanded(child:TextField(controller:input,onSubmitted:(_)=>run(),style:const TextStyle(color:Colors.white,fontFamily:'monospace',fontSize:12),decoration:const InputDecoration(hintText:'Terminal-Befehl…',hintStyle:TextStyle(color:NexusColors.textMuted),border:InputBorder.none))),IconButton(onPressed:running?null:run,icon:Icon(running?Icons.hourglass_top:Icons.play_arrow,color:NexusColors.accentPrimary))])]));
}
