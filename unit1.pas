//Copyright 2022 Andrey S. Ionisyan (anserion@gmail.com)
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.

unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ExtDlgs, FPCanvas, LCLintf, LCLType;

type

  { TForm1 }

  TForm1 = class(TForm)
    Bevel_Layer3: TBevel;
    Bevel_receptors: TBevel;
    BTN_nw_reset: TButton;
    BTN_s_clear: TButton;
    BTN_BMPFile_load: TButton;
    CB_timer: TCheckBox;
    CB_noise: TCheckBox;
    CB_contrast: TCheckBox;
    Edit_L1_inputs: TEdit;
    Edit_contrast: TEdit;
    Edit_noise: TEdit;
    Edit_timer: TEdit;
    Edit_N_L1: TEdit;
    Edit_N_L2: TEdit;
    Edit_N_L3: TEdit;
    Label1: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    Label7: TLabel;
    Label8: TLabel;
    Label9: TLabel;
    Label_Layer3: TLabel;
    Label2: TLabel;
    OpenPictureDialog: TOpenPictureDialog;
    PB_Layer3: TPaintBox;
    PB_receptors: TPaintBox;
    Timer1: TTimer;
    procedure BTN_BMPFile_loadClick(Sender: TObject);
    procedure BTN_nw_resetClick(Sender: TObject);
    procedure BTN_s_clearClick(Sender: TObject);
    procedure CB_contrastChange(Sender: TObject);
    procedure CB_noiseChange(Sender: TObject);
    procedure CB_timerChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure PB_Layer3Paint(Sender: TObject);
    procedure PB_receptorsPaint(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private
    procedure Forward_step;
    procedure BackTraceError_step;
    procedure BackTraceLearn_step;
  public

  end;

const
  s_width=256;
  s_height=256;

  n_L1_inputs=4096;
  n_L1=1000;
  n_L2=5;
  n_L3=s_width*s_height;

  a_bpe=1;
var
  Form1: TForm1;
  cameraBitmap,receptorsBitmap,L3_bitmap:TBitmap;
  img_buffer:array[0..s_width*s_height-1]of integer;
  S_elements: array[0..s_width*s_height-1]of integer;
  Target_elements: array[0..s_width*s_height-1]of integer;

  L1_w:array[0..n_L1-1,0..n_L1_inputs-1] of integer;
  L1_scalar:array[0..n_L1-1] of integer;
  L1_out:array[0..n_L1-1] of integer;
  L1_map_S_x:array[0..n_L1-1,0..n_L1_inputs-1] of integer;
  L1_map_S_y:array[0..n_L1-1,0..n_L1_inputs-1] of integer;

  L2_w:array[0..n_L2-1,0..n_L1-1] of integer;
  L2_scalar:array[0..n_L2-1] of integer;
  L2_out:array[0..n_L2-1] of integer;

  L3_w:array[0..n_L3-1,0..n_L2-1] of integer;
  L3_scalar:array[0..n_L3-1] of integer;
  L3_out:array[0..n_L3-1] of integer;

  sigma1:array[0..n_L1-1] of integer;
  sigma2:array[0..n_L2-1] of integer;
  sigma3:array[0..n_L3-1] of integer;

  error_target_to_L3:array[0..n_L3-1] of integer;
  error_L3_to_L2:array[0..n_L2-1] of integer;
  error_L2_to_L1:array[0..n_L1-1] of integer;

  BackTrace_flag:boolean;
  sigmoid_ROM: array[0..255]of integer;
  der_sigmoid_ROM: array[0..255]of integer;

implementation

{$R *.lfm}

//sigmoid:=1/(1+exp(-x));
function sigmoid(x:integer):integer;
var k:integer;
begin
  k:=128+x; // remember do *16 outside function before "div"
  if k>255 then k:=255;
  if k<0 then k:=0;
  sigmoid:=sigmoid_ROM[k];
end;

//der_sigmoid:=y*(1-y);
function der_sigmoid(y:integer):integer;
var k:integer;
begin
  k:=y; // remember do *256 outside function befire "div"
  if k>255 then k:=255;
  if k<0 then k:=0;
  der_sigmoid:=der_sigmoid_ROM[k];
end;


{ TForm1 }

procedure TForm1.Forward_step;
var i,k:integer;
begin
  BackTrace_flag:=false;

  for k:=0 to n_L1-1 do
  begin
    L1_scalar[k]:=0;
    for i:=0 to n_L1_inputs-1 do
      L1_scalar[k]:=L1_scalar[k]+L1_w[k,i]*S_elements[L1_map_S_x[k,i]+s_width*L1_map_S_y[k,i]];
    L1_out[k]:=sigmoid(L1_scalar[k]*16 div (256*256));
  end;

  for k:=0 to n_L2-1 do
  begin
    L2_scalar[k]:=0;
    for i:=0 to n_L1-1 do L2_scalar[k]:=L2_scalar[k]+L2_w[k,i]*L1_out[i];
    L2_out[k]:=sigmoid(L2_scalar[k]*16 div (256*256));
  end;

  for k:=0 to n_L3-1 do
  begin
    L3_scalar[k]:=0;
    for i:=0 to n_L2-1 do L3_scalar[k]:=L3_scalar[k]+L3_w[k,i]*L2_out[i];
    L3_out[k]:=sigmoid(L3_scalar[k]*16 div (256*256));
  end;
end;

procedure TForm1.BackTraceError_step;
var i,k:integer;
begin
  for i:=0 to n_L3-1 do
  begin
    error_target_to_L3[i]:=-(Target_elements[i]-L3_out[i]);
    sigma3[i]:=error_target_to_L3[i]*der_sigmoid(L3_out[i]) div 256;
  end;

  for i:=0 to n_L2-1 do
  begin
    error_L3_to_L2[i]:=0;
    for k:=0 to n_L3-1 do
        error_L3_to_L2[i]:=error_L3_to_L2[i]+sigma3[k]*L3_w[k,i] div 256;
    sigma2[i]:=error_L3_to_L2[i]*der_sigmoid(L2_out[i]) div (256*256);
  end;

  for i:=0 to n_L1-1 do
  begin
    error_L2_to_L1[i]:=0;
    for k:=0 to n_L2-1 do
      error_L2_to_L1[i]:=error_L2_to_L1[i]+sigma2[k]*L2_w[k,i] div 256;
    sigma1[i]:=error_L2_to_L1[i]*der_sigmoid(L1_out[i]) div (256*256);
  end;
end;

procedure TForm1.BackTraceLearn_step;
var i,k:integer;
begin
  for i:=0 to n_L1-1 do
    for k:=0 to n_L1_inputs-1 do
      L1_w[i,k]:=L1_w[i,k]-(sigma1[i]*S_elements[L1_map_S_x[i,k]+s_width*L1_map_S_y[i,k]]) div 256;

  for i:=0 to n_L2-1 do
    for k:=0 to n_L1-1 do
      L2_w[i,k]:=L2_w[i,k]-(sigma2[i]*L1_out[k]) div 256;

  for i:=0 to n_L3-1 do
      for k:=0 to n_L2-1 do
        L3_w[i,k]:=L3_w[i,k]-(sigma3[i]*L2_out[k]) div 256;
end;

procedure TForm1.PB_Layer3Paint(Sender: TObject);
var i:integer; contrast_value:real; C:real;
var dst_bpp:integer; dst_ptr:PByte; R,G,B:byte;
begin
  if CB_contrast.Checked
  then contrast_value:=StrToFloat(Edit_contrast.text)/100
  else contrast_value:=1;

  for i:=0 to s_width*s_height-1 do
  begin
    C:=(L3_out[i]-256)*contrast_value+256;
    if C<0 then C:=0;
    if C>255 then C:=255;
    img_buffer[i]:=trunc(C);
  end;

  L3_Bitmap.BeginUpdate(false);
  dst_ptr:=L3_Bitmap.RawImage.Data;
  dst_bpp:=L3_Bitmap.RawImage.Description.BitsPerPixel div 8;

  for i:=0 to s_width*s_height-1 do
  begin
     R:=img_buffer[i]; G:=R; B:=R;
     dst_ptr^:=B; (dst_ptr+1)^:=G; (dst_ptr+2)^:=R; inc(dst_ptr,dst_bpp);
  end;
  L3_Bitmap.EndUpdate(false);
  PB_Layer3.Canvas.StretchDraw(Rect(0,0,PB_Layer3.Width,PB_Layer3.Height),L3_Bitmap);
end;

procedure TForm1.PB_receptorsPaint(Sender: TObject);
var i:integer; dst_bpp:integer; dst_ptr:PByte; R,G,B:byte;
begin
  for i:=0 to s_width*s_height-1 do img_buffer[i]:=S_elements[i];

  receptorsBitmap.BeginUpdate(false);
  dst_ptr:=receptorsBitmap.RawImage.Data;
  dst_bpp:=receptorsBitmap.RawImage.Description.BitsPerPixel div 8;
  for i:=0 to s_width*s_height-1 do
  begin
     R:=img_buffer[i]; G:=R; B:=R;
     dst_ptr^:=B; (dst_ptr+1)^:=G; (dst_ptr+2)^:=R; inc(dst_ptr,dst_bpp);
  end;
  receptorsBitmap.EndUpdate(false);
  PB_receptors.Canvas.StretchDraw(
      Rect(0,0,PB_receptors.width,PB_receptors.Height),
      receptorsBitmap);
end;

procedure TForm1.FormCreate(Sender: TObject);
var i:LongInt;
begin
  for i:=0 to 255 do sigmoid_ROM[i]:=trunc(255/(1+exp(-(i-128)/16)));
  for i:=0 to 255 do der_sigmoid_ROM[i]:=trunc(i*(1-i/256));
  Edit_N_L1.text:=IntToStr(n_L1);
  Edit_L1_inputs.text:=IntToStr(n_L1_inputs);
  Edit_N_L2.text:=IntToStr(n_L2);
  Edit_N_L3.text:=IntToStr(n_L3);
  cameraBitmap:=TBitmap.Create;
  cameraBitmap.SetSize(s_width,s_height);
  receptorsBitmap:=TBitmap.Create;
  receptorsBitmap.SetSize(s_width,s_height);
  L3_Bitmap:=TBitmap.Create;
  L3_Bitmap.SetSize(s_width,s_height);
  for i:=0 to s_width*s_height-1 do img_buffer[i]:=0;
  for i:=0 to s_width*s_height-1 do S_elements[i]:=0;
  BTN_nw_resetClick(self);
end;

procedure TForm1.Timer1Timer(Sender: TObject);
var i:integer; noise_value:integer;
    src_bpp:integer; Src_ptr:PByte; R,G,B:word;
begin
  src_ptr:=cameraBitmap.RawImage.Data;
  src_bpp:=cameraBitmap.RawImage.Description.BitsPerPixel div 8;
  for i:=0 to s_width*s_height-1 do
  begin
    R:=(src_ptr+2)^; G:=(src_ptr+1)^; B:=src_ptr^; inc(src_ptr,src_bpp);
    img_buffer[i]:=(R+G+B) div 3;
  end;
  for i:=0 to n_L3-1 do S_elements[i]:=img_buffer[i];

  if CB_noise.Checked then
  begin
    noise_value:=StrToInt(Edit_noise.text);
    for i:=0 to n_L3-1 do
      if random(100)<=noise_value then S_elements[i]:=random(255);
  end;

  for i:=0 to n_L3-1 do Target_elements[i]:=S_elements[i];

  Forward_step;
  BackTraceError_step;
  BackTraceLearn_step;
  PB_receptorsPaint(self);
  PB_Layer3Paint(self);
end;

procedure TForm1.BTN_nw_resetClick(Sender: TObject);
var i,k:integer;
begin
     randomize;
     for k:=0 to n_L1-1 do
       for i:=0 to n_L1_inputs-1 do
       begin
         L1_w[k,i]:=random(16)-8;
         L1_map_S_x[k,i]:=random(s_width);
         L1_map_S_y[k,i]:=random(s_height);
       end;

     for k:=0 to n_L2-1 do
       for i:=0 to n_L1-1 do
         L2_w[k,i]:=random(16)-8;

     for k:=0 to n_L3-1 do
       for i:=0 to n_L2-1 do
         L3_w[k,i]:=random(16)-8;

     Edit_N_L3.text:=IntToStr(n_L3);
     BackTrace_flag:=false;
     Forward_step;
     PB_Layer3Paint(PB_Layer3);
end;

procedure TForm1.BTN_BMPFile_loadClick(Sender: TObject);
var bitmap:TBitmap;
begin
  if OpenPictureDialog.execute then
  begin
     bitmap:=TBitmap.Create;
     bitmap.LoadFromFile(OpenPictureDialog.FileName);
     cameraBitmap.Canvas.StretchDraw(Rect(0,0,s_width-1,s_height-1),bitmap);
     bitmap.Free;
     Timer1Timer(self);
  end;
end;

procedure TForm1.BTN_s_clearClick(Sender: TObject);
var i:integer;
begin
  cameraBitmap.Canvas.Clear;
  for i:=0 to n_L3-1 do S_elements[i]:=0;
  Timer1Timer(self);
end;

procedure TForm1.CB_contrastChange(Sender: TObject);
begin
  Edit_contrast.ReadOnly:=CB_contrast.Checked;
end;

procedure TForm1.CB_noiseChange(Sender: TObject);
begin
    Edit_noise.ReadOnly:=CB_noise.Checked;
end;

procedure TForm1.CB_timerChange(Sender: TObject);
begin
  Timer1.Interval:=StrToInt(Edit_timer.Text);
  Timer1.enabled:=CB_timer.Checked;
end;

end.

