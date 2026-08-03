import fs from 'node:fs/promises';
import { Presentation, PresentationFile } from '@oai/artifact-tool';

const OUT='C:/Users/capte/Documents/object703/AI初学者_拟合与神经网络_例子叙事版.pptx';
const RENDER='C:/Users/capte/Documents/object703/.tmp_ai_fitting_deck/rendered';
const p=Presentation.create({slideSize:{width:1280,height:720}});
const C={ink:'#152033',muted:'#657083',blue:'#2979FF',cyan:'#19B5C5',orange:'#FF9A3D',red:'#E95A5A',green:'#23A36D',paper:'#F7F8FA',grid:'#DDE3EA',white:'#FFFFFF',paleBlue:'#EAF2FF',paleOrange:'#FFF1E4',paleGreen:'#E9F7F0'};
const FONT='Microsoft YaHei';
function box(slide,x,y,w,h,fill=C.white,r=18,line='none'){return slide.shapes.add({geometry:r?'roundRect':'rect',position:{left:x,top:y,width:w,height:h},fill,line:{style:'solid',fill:line,width:line==='none'?0:1},borderRadius:r?'rounded-xl':undefined});}
function txt(slide,text,x,y,w,h,size=24,color=C.ink,bold=false,align='left'){const s=slide.shapes.add({geometry:'textbox',position:{left:x,top:y,width:w,height:h},fill:'none',line:{style:'solid',fill:'none',width:0}});s.text=text;s.text.style={fontSize:size,typeface:FONT,color,bold,alignment:align,verticalAlignment:'middle',autoFit:'shrinkText'};return s;}
function line(slide,x,y,w,h,color=C.grid,width=2){const left=w<0?x+w:x,top=h<0?y+h:y;return slide.shapes.add({geometry:'straightConnector1',position:{left,top,width:Math.abs(w),height:Math.abs(h),horizontalFlip:w<0,verticalFlip:h<0},fill:'none',line:{style:'solid',fill:color,width}});}
function dot(slide,x,y,r=8,color=C.blue){return slide.shapes.add({geometry:'ellipse',position:{left:x-r,top:y-r,width:r*2,height:r*2},fill:color,line:{style:'solid',fill:color,width:0}});}
function title(slide,t,n){txt(slide,t,56,34,1080,68,38,C.ink,true);txt(slide,String(n).padStart(2,'0'),1170,40,54,30,15,C.muted,false,'right');line(slide,56,110,1168,0,C.grid,1);}
function notes(slide,body,sources=''){slide.speakerNotes.textFrame.setText(`${body}\n\n[Sources]\n${sources||'No external assets. Educational synthesis by OpenAI.'}`);}
function base(){const s=p.slides.add();s.background.fill=C.paper;return s;}
function arrow(slide,x,y,w,h,color=C.blue){line(slide,x,y,w,h,color,4);slide.shapes.add({geometry:'triangle',position:{left:x+w-10,top:y+h-7,width:16,height:14},rotation:h===0?90:135,fill:color,line:{style:'solid',fill:color,width:0}});}
function neuron(slide,cx,cy,label,fill=C.paleBlue){slide.shapes.add({geometry:'ellipse',position:{left:cx-28,top:cy-28,width:56,height:56},fill,line:{style:'solid',fill:C.blue,width:2}});txt(slide,label,cx-22,cy-18,44,36,18,C.ink,true,'center');}
function poly(slide,pts,color=C.blue,width=4){for(let i=0;i<pts.length-1;i++)line(slide,pts[i][0],pts[i][1],pts[i+1][0]-pts[i][0],pts[i+1][1]-pts[i][1],color,width);}

// 1
{
 const s=base(); txt(s,'AI 入门',56,48,240,34,22,C.blue,true); txt(s,'从“拟合一条线”\n到“训练一个神经网络”',56,174,900,210,62,C.ink,true); txt(s,'用直觉、图形和最少公式，理解机器学习真正学到了什么',60,432,850,56,26,C.muted); box(s,60,550,1160,7,C.blue,0); txt(s,'拟合  ·  泛化  ·  神经元  ·  训练  ·  深度网络',60,578,800,40,20,C.ink,true); notes(s,'开场：AI 并不是“突然变聪明”，而是在数据中不断调整参数，找到能预测新样本的规律。','Arthur Samuel (1959), Some Studies in Machine Learning Using the Game of Checkers.');
}
//2
{
 const s=base();title(s,'机器学习的核心任务：从例子中找到可重复的规律',2);
 txt(s,'输入 x',80,185,160,48,28,C.blue,true,'center');arrow(s,245,210,140,0);box(s,405,155,390,125,C.white,20,C.grid);txt(s,'模型 f(x; θ)',425,175,350,48,34,C.ink,true,'center');txt(s,'θ = 模型可调整的参数',430,225,340,30,18,C.muted,false,'center');arrow(s,810,210,140,0);txt(s,'预测 ŷ',970,185,190,48,28,C.green,true,'center');
 txt(s,'训练 = 调参数，让预测更接近答案',160,364,960,64,38,C.ink,true,'center');
 txt(s,'数据告诉模型“哪里错了”  →  损失函数衡量错误  →  优化器修改参数',150,468,980,56,24,C.muted,false,'center');
 notes(s,'强调：模型不是存储答案，而是在参数 θ 中压缩规律。','Mitchell, Machine Learning (1997), definition of learning from experience.');
}
//3
{
 const s=base();title(s,'简单例子：用学习时间预测测验成绩',3);
 box(s,56,145,760,500,C.white,18,C.grid); line(s,120,585,630,0,C.ink,2);line(s,120,585,0,-370,C.ink,2);
 const pts=[[150,530],[205,500],[265,475],[325,430],[390,415],[455,355],[520,340],[585,285],[650,250],[710,205]];pts.forEach(([x,y])=>dot(s,x,y,8,C.blue));line(s,145,535,575,-330,C.orange,5);
 txt(s,'已有经验',850,190,300,44,28,C.blue,true);txt(s,'学习时间 x 与成绩 y',850,235,330,42,20,C.muted);
 txt(s,'拟合曲线',850,330,300,44,28,C.orange,true);txt(s,'模型对规律的猜测',850,375,330,42,20,C.muted);
 txt(s,'学到趋势后，可以预测新的学习时长',850,490,330,88,25,C.ink,true);
 notes(s,'散点表示过去学生的学习时间与成绩。直线不必经过每个点，只要能概括整体趋势并预测新样本。','Hastie, Tibshirani & Friedman, The Elements of Statistical Learning (2009).');
}
//4
{
 const s=base();title(s,'第一步：一次函数只需要学习两个参数',4);
 box(s,55,145,720,485,C.white,18,C.grid);line(s,120,560,585,0,C.ink,2);line(s,120,560,0,-335,C.ink,2);
 [[150,515],[210,475],[275,450],[340,405],[410,370],[480,330],[555,278],[630,250],[690,205]].forEach(q=>dot(s,q[0],q[1],7,C.blue));
 line(s,140,525,540,-305,C.orange,5);txt(s,'ŷ = ax + b',815,175,350,70,44,C.ink,true,'center');
 txt(s,'a：斜率',850,285,280,44,29,C.orange,true);txt(s,'控制线有多“斜”',850,330,300,36,21,C.muted);
 txt(s,'b：截距',850,410,280,44,29,C.blue,true);txt(s,'控制整条线向上或向下',850,455,310,36,21,C.muted);
 txt(s,'训练要做的事：找到更合适的 a 和 b',805,555,390,58,25,C.ink,true,'center');
 notes(s,'一次函数是最简单的可学习模型。参数 a、b 决定模型形状。','Hastie, Tibshirani & Friedman (2009), linear regression.');
}
//5
{
 const s=base();title(s,'再看一个例子：气温与用电量并不是直线关系',5);
 box(s,55,145,760,480,C.white,18,C.grid);line(s,120,560,625,0,C.ink,2);line(s,120,560,0,-335,C.ink,2);
 const pts=[[150,255],[205,320],[265,390],[325,450],[385,485],[445,460],[505,405],[565,330],[625,265],[690,230]];pts.forEach(q=>dot(s,q[0],q[1],7,C.blue));
 poly(s,[[145,250],[205,320],[265,392],[325,450],[385,482],[445,458],[505,400],[565,330],[625,270],[700,220]],C.orange,5);
 txt(s,'天气舒适时',865,190,260,42,26,C.green,true);txt(s,'制冷、制热需求都较低',865,235,300,58,21,C.muted);
 txt(s,'天气过冷或过热时',865,340,290,42,26,C.orange,true);txt(s,'用电量再次上升，关系发生弯曲',865,385,300,58,21,C.muted);
 txt(s,'能力越强，越要防止“记住噪声”',830,535,355,60,25,C.ink,true,'center');
 notes(s,'此处使用概念性数据说明非线性关系，并非真实统计数据。多项式、样条或分段函数都能增强表达能力。','Conceptual example; Hastie, Tibshirani & Friedman (2009), polynomial regression and model complexity.');
}
//6
{
 const s=base();title(s,'当现实越来越复杂：我们该手工选择哪一种函数？',6);
 txt(s,'预测房价',70,165,250,46,28,C.blue,true);txt(s,'面积 · 地段 · 楼龄 · 楼层 · 配套',70,215,440,38,21,C.muted);
 txt(s,'识别图片',70,320,250,46,28,C.orange,true);txt(s,'成千上万个像素彼此组合',70,370,440,38,21,C.muted);
 txt(s,'理解语言',70,475,250,46,28,C.green,true);txt(s,'词语含义随上下文不断变化',70,525,440,38,21,C.muted);
 line(s,535,155,0,430,C.grid,2);txt(s,'输入很多',625,170,230,48,30,C.ink,true,'center');txt(s,'关系非线性',925,170,230,48,30,C.ink,true,'center');
 arrow(s,720,270,250,0,C.orange);txt(s,'复杂度上升',760,220,180,38,22,C.orange,true,'center');
 txt(s,'能不能让模型自己学习“该组合哪些简单函数”？',610,375,560,115,40,C.ink,true,'center');
 box(s,720,525,350,62,C.ink,16,'none');txt(s,'这就是神经网络要回答的问题',740,535,310,42,22,C.white,true,'center');
 notes(s,'通过三个例子抛出转折：低维问题可手工选函数，高维复杂关系需要自动学习特征组合。','LeCun, Bengio & Hinton (2015), Deep learning, Nature.');
}
//7
{
 const s=base();title(s,'灵感来自大脑：神经元通过连接接收、整合并传递信号',7);
 // connectors first
 [[235,225],[235,355],[235,485]].forEach(q=>line(s,q[0],q[1],287,355-q[1],C.cyan,4));line(s,578,355,232,0,C.blue,6);line(s,810,355,220,-95,C.orange,4);line(s,810,355,220,0,C.orange,4);line(s,810,355,220,95,C.orange,4);
 [[205,225],[205,355],[205,485]].forEach((q,i)=>{dot(s,q[0],q[1],22,[C.cyan,C.blue,C.green][i]);});
 neuron(s,550,355,'整合',C.paleBlue);dot(s,1050,260,18,C.orange);dot(s,1050,355,18,C.orange);dot(s,1050,450,18,C.orange);
 txt(s,'树突：接收信号',85,555,250,42,24,C.cyan,true,'center');txt(s,'细胞体：整合信号',420,555,260,42,24,C.blue,true,'center');txt(s,'轴突：把信号传给下一批神经元',770,555,390,42,24,C.orange,true,'center');
 txt(s,'人工神经网络借用了“许多简单单元彼此连接”的思想',220,635,840,40,28,C.ink,true,'center');
 notes(s,'人工神经网络受到生物神经系统启发，但只是高度简化的数学模型，并不等同于真实大脑。','McCulloch & Pitts (1943), A Logical Calculus of Ideas Immanent in Nervous Activity.');
}
//8
{
 const s=base();title(s,'神经网络把许多简单函数叠加成复杂曲线',8);
 box(s,55,145,560,455,C.white,18,C.grid);line(s,105,535,460,0,C.ink,2);line(s,105,535,0,-315,C.ink,2);
 poly(s,[[120,490],[210,490],[315,390],[410,390],[540,255]],'#B8D0FF',5);poly(s,[[120,455],[270,455],[365,315],[540,315]],'#99E0E6',5);poly(s,[[120,520],[350,520],[460,365],[540,365]],'#FFD1A8',5);
 poly(s,[[120,495],[190,470],[260,420],[330,350],[400,305],[470,280],[540,245]],C.blue,8);
 txt(s,'多个简单“折线函数”',145,565,400,30,20,C.muted,false,'center');
 arrow(s,640,365,100,0,C.blue);box(s,765,175,440,350,C.paleBlue,18,'none');txt(s,'神经网络',825,205,320,52,34,C.blue,true,'center');
 txt(s,'每个神经元学习一个简单变换',815,285,340,50,23,C.ink,false,'center');txt(s,'多层组合后，能逼近复杂规律',815,365,340,50,25,C.ink,true,'center');txt(s,'参数 = 所有连接的权重与偏置',815,445,340,42,21,C.muted,false,'center');
 txt(s,'不是换了一种目标：仍然是在“拟合”',250,630,780,40,28,C.ink,true,'center');notes(s,'这里展示的是直觉：ReLU 神经元形成分段线性基函数，多层网络组合后可表达复杂函数。','Cybenko (1989), Approximation by superpositions of a sigmoidal function; Hornik (1991).');
}
//9
{
 const s=base();title(s,'损失函数：把“差得多远”变成一个数字',9);
 txt(s,'真实值 y',80,190,180,44,26,C.ink,true);txt(s,'预测值 ŷ',80,275,180,44,26,C.blue,true);line(s,280,212,350,0,C.ink,3);line(s,280,297,285,0,C.blue,3);line(s,570,220,0,70,C.red,5);txt(s,'误差',600,230,120,44,24,C.red,true);
 box(s,760,160,420,190,C.white,18,C.grid);txt(s,'均方误差 MSE',800,188,340,42,28,C.ink,true,'center');txt(s,'平均 (y − ŷ)²',800,245,340,64,38,C.blue,true,'center');
 txt(s,'训练目标',80,420,220,46,26,C.muted,true);txt(s,'让损失越来越小',80,470,600,74,46,C.ink,true);arrow(s,680,505,180,0,C.green);txt(s,'预测更接近真实',880,480,300,52,26,C.green,true);
 notes(s,'平方让正负误差不会抵消，也会更重地惩罚大误差。','Goodfellow, Bengio & Courville, Deep Learning (2016), Ch. 5.');
}
//10
{
 const s=base();title(s,'梯度下降：沿着误差下降最快的方向调整参数',10);
 txt(s,'损失 L(θ)',70,145,180,40,25,C.red,true);line(s,120,590,670,0,C.ink,2);line(s,120,590,0,-380,C.ink,2);
 poly(s,[[150,250],[210,315],[275,390],[345,465],[420,525],[500,555],[575,525],[650,455],[725,340]],C.orange,6);
 const steps=[[690,375],[625,470],[570,525],[520,550]];steps.forEach((q,i)=>{dot(s,q[0],q[1],11,i===steps.length-1?C.green:C.blue);txt(s,`θ${i}`,q[0]-22,q[1]-45,44,30,18,i===steps.length-1?C.green:C.blue,true,'center');if(i<steps.length-1)arrow(s,q[0]-5,q[1]+10,steps[i+1][0]-q[0]+10,steps[i+1][1]-q[1]-5,C.blue);});
 txt(s,'参数 θ',705,605,100,34,22,C.ink,true);box(s,835,160,355,380,C.white,18,C.grid);
 txt(s,'每一步都问',875,190,275,38,25,C.muted,true,'center');txt(s,'“参数往哪边改，\n损失会下降？”',875,245,275,90,30,C.ink,true,'center');
 txt(s,'θ ← θ − η · ∇L(θ)',870,365,290,66,31,C.blue,true,'center');txt(s,'η：学习率（步长）',875,450,280,38,21,C.muted,false,'center');
 txt(s,'最低点附近 = 当前数据经验下更好的参数',260,635,760,40,25,C.ink,true,'center');notes(s,'梯度给出损失上升最快方向，因此减去梯度会下降。学习率控制每一步大小。','Goodfellow, Bengio & Courville (2016), Ch. 8, gradient-based optimization.');
}
//11
{
 const s=base();title(s,'“经验”如何变成参数：一次训练迭代的完整路径',11);
 const items=[['已有经验','输入 x 与答案 y',C.paleBlue,C.blue],['做出预测','ŷ = f(x; θ)',C.white,C.ink],['计算误差','L(y, ŷ)',C.paleOrange,C.orange],['求梯度','∇θL：该往哪改', '#FCECEC',C.red],['更新参数','θ ← θ − η∇θL',C.paleGreen,C.green]];
 items.forEach((it,i)=>{const x=35+i*245;box(s,x,205,215,240,it[2],18,i===1?C.grid:'none');txt(s,it[0],x+18,230,179,44,26,it[3],true,'center');txt(s,it[1],x+20,315,175,70,21,C.ink,false,'center');if(i<4)arrow(s,x+215,325,30,0,C.muted);});
 line(s,1140,485,-980,0,C.blue,4);txt(s,'带着新参数，再看一遍经验',430,505,520,46,25,C.blue,true,'center');txt(s,'每次迭代只改一点点；大量迭代后，参数逐渐编码了数据中的规律',185,600,910,54,28,C.ink,true,'center');notes(s,'训练样本提供误差信号；梯度下降将信号转换为参数更新。循环重复形成学习。','Rumelhart, Hinton & Williams (1986); Goodfellow et al. (2016).');
}
//12
{
 const s=base();title(s,'三种拟合状态：太简单、刚刚好、太复杂',12);
 const xs=[56,435,814], heads=['欠拟合','恰当拟合','过拟合'], cols=[C.red,C.green,C.orange], desc=['训练集也学不好','抓住主要趋势','记住噪声，遇到新数据失灵'];
 xs.forEach((x,i)=>{box(s,x,150,350,390,C.white,18,C.grid);txt(s,heads[i],x+25,170,300,44,30,cols[i],true,'center');line(s,x+48,480,255,0,C.ink,1);line(s,x+48,480,0,-220,C.ink,1);[[x+75,440],[x+115,390],[x+160,375],[x+205,315],[x+250,285],[x+290,240]].forEach(q=>dot(s,q[0],q[1],5,C.blue)); if(i===0) line(s,x+65,405,235,-45,cols[i],5); if(i===1) line(s,x+65,445,235,-190,cols[i],5); if(i===2){const seg=[[x+65,445],[x+105,365],[x+145,410],[x+185,290],[x+225,330],[x+300,235]];for(let j=0;j<seg.length-1;j++)line(s,seg[j][0],seg[j][1],seg[j+1][0]-seg[j][0],seg[j+1][1]-seg[j][1],cols[i],4);}txt(s,desc[i],x+20,558,310,52,21,C.muted,false,'center');});
 notes(s,'这一页是全篇核心。过拟合并非训练不够好，恰恰是训练数据拟合得“太好”。','Hastie, Tibshirani & Friedman (2009), bias–variance tradeoff.');
}
//13
{
 const s=base();title(s,'真正的考试，是模型没见过的新数据',13);
 box(s,60,160,500,390,C.paleBlue,18,'none');txt(s,'训练集',95,188,420,48,30,C.blue,true);txt(s,'用来学习参数',95,250,420,40,24,C.ink);txt(s,'模型可以反复查看',95,305,420,40,24,C.ink);txt(s,'训练误差通常持续下降',95,360,420,40,24,C.ink);
 box(s,720,160,500,390,C.paleGreen,18,'none');txt(s,'验证 / 测试集',755,188,430,48,30,C.green,true);txt(s,'用来检验泛化',755,250,430,40,24,C.ink);txt(s,'模型训练时不能偷看',755,305,430,40,24,C.ink);txt(s,'新数据表现才有意义',755,360,430,40,24,C.ink);
 arrow(s,575,350,120,0,C.orange);txt(s,'泛化',585,285,100,36,23,C.orange,true,'center');txt(s,'好模型 = 不只会做练习题，还会做新题',175,600,930,52,34,C.ink,true,'center');
 notes(s,'类比考试：训练集是练习题，测试集是从未见过的考题。','Goodfellow, Bengio & Courville (2016), Ch. 5.');
}
//14
{
 const s=base();title(s,'一个人工神经元：把生物灵感变成数学计算',14);
 ['面积 x₁','楼层 x₂','房龄 x₃'].forEach((v,i)=>{txt(s,v,60,180+i*110,160,46,24,C.ink,true);arrow(s,230,203+i*110,220,(300-(203+i*110)),[C.blue,C.cyan,C.orange][i]);});
 neuron(s,500,300,'Σ',C.paleBlue);arrow(s,535,300,150,0,C.blue);box(s,710,250,220,100,C.paleOrange,18,'none');txt(s,'激活函数',730,272,180,48,26,C.orange,true,'center');arrow(s,945,300,120,0,C.green);txt(s,'输出 ŷ',1080,278,140,44,27,C.green,true,'center');
 txt(s,'z = w₁x₁ + w₂x₂ + w₃x₃ + b',250,465,780,58,34,C.ink,true,'center');txt(s,'权重 w 表示“每个输入有多重要”',330,540,620,42,23,C.muted,false,'center');
 notes(s,'神经元先做加权求和，再经过激活函数。权重和偏置就是要拟合的参数。','McCulloch & Pitts (1943); Rosenblatt (1958).');
}
//15
{
 const s=base();title(s,'激活函数让网络不只会画直线',15);
 box(s,65,160,470,390,C.white,18,C.grid);txt(s,'没有激活函数',95,185,410,44,28,C.red,true,'center');line(s,130,475,330,0,C.ink,1);line(s,130,475,0,-220,C.ink,1);line(s,150,430,285,-165,C.red,5);txt(s,'多层叠加后仍等价于一条直线',105,520,390,52,21,C.muted,false,'center');
 box(s,745,160,470,390,C.white,18,C.grid);txt(s,'加入 ReLU 等激活函数',775,185,410,44,28,C.green,true,'center');line(s,810,475,330,0,C.ink,1);line(s,810,475,0,-220,C.ink,1);line(s,830,430,105,0,C.green,5);line(s,935,430,165,-170,C.green,5);txt(s,'可以组合出弯曲、分段的边界',785,520,390,52,21,C.muted,false,'center');
 txt(s,'ReLU(z) = max(0, z)',420,610,440,48,30,C.blue,true,'center');notes(s,'激活函数提供非线性，这是深层网络表达复杂关系的关键。','Nair & Hinton (2010), Rectified Linear Units Improve Restricted Boltzmann Machines.');
}
//16
{
 const s=base();title(s,'多层神经网络：上一层的输出，成为下一层的输入',16);
 const cols=[[130,3],[420,5],[720,4],[1030,2]];const labels=['输入层','隐藏层 1','隐藏层 2','输出层'];
 // connectors first
 for(let c=0;c<cols.length-1;c++){const [x,n]=cols[c],[nx,nn]=cols[c+1];for(let i=0;i<n;i++)for(let j=0;j<nn;j++){const y=210+i*(280/(Math.max(1,n-1))),ny=210+j*(280/(Math.max(1,nn-1)));line(s,x+28,y,nx-x-56,ny-y,'#C7D5EA',1);}}
 cols.forEach(([x,n],ci)=>{for(let i=0;i<n;i++)neuron(s,x,210+i*(280/(Math.max(1,n-1))),ci===0?`x${i+1}`:'',ci===3?C.paleGreen:C.paleBlue);txt(s,labels[ci],x-80,560,160,42,23,ci===3?C.green:C.ink,true,'center');});
 txt(s,'每一层都在重新组合特征：边缘 → 形状 → 对象',250,625,780,42,28,C.ink,true,'center');notes(s,'层数增加并不自动保证更好，但为模型提供了逐层组合特征的能力。','LeCun, Bengio & Hinton (2015), Deep learning, Nature.');
}
//17
{
 const s=base();title(s,'训练循环：预测、算错、回传、更新',17);
 const items=[['① 前向传播','根据当前参数产生预测',C.paleBlue,C.blue],['② 计算损失','比较预测与真实答案',C.paleOrange,C.orange],['③ 反向传播','计算每个参数应承担多少错误', '#FCECEC',C.red],['④ 更新参数','沿着损失下降的方向迈一步',C.paleGreen,C.green]];
 items.forEach((it,i)=>{const x=55+i*305;box(s,x,205,270,250,it[2],18,'none');txt(s,it[0],x+22,230,226,46,27,it[3],true,'center');txt(s,it[1],x+30,305,210,90,21,C.ink,false,'center');if(i<3)arrow(s,x+270,330,35,0,C.muted);});
 txt(s,'不断重复，直到验证集表现不再改善',220,540,840,58,34,C.ink,true,'center');txt(s,'学习率决定每次更新迈多大一步',360,610,560,36,21,C.muted,false,'center');notes(s,'反向传播不是“把答案倒着传”，而是用链式法则计算梯度。','Rumelhart, Hinton & Williams (1986), Learning representations by back-propagating errors.');
}
//18
{
 const s=base();title(s,'怎样减轻过拟合？让模型少记噪声、多学规律',18);
 const data=[['更多、更有代表性的数据','扩大模型看到的世界',C.blue],['正则化 / 权重衰减','限制参数变得过于极端',C.orange],['Dropout','训练时随机关闭部分神经元',C.red],['早停','验证误差变坏前停止训练',C.green]];
 data.forEach((d,i)=>{const y=155+i*118;txt(s,String(i+1).padStart(2,'0'),70,y,70,54,30,d[2],true,'center');line(s,160,y+27,170,0,d[2],4);txt(s,d[0],365,y,390,48,27,C.ink,true);txt(s,d[1],780,y,400,48,22,C.muted);});
 notes(s,'措施的共同目标是减少模型对训练集偶然细节的依赖。','Srivastava et al. (2014), Dropout; Prechelt (1998), Early Stopping.');
}
//19
{
 const s=base();title(s,'从普通网络到注意力：模型学会“该看哪里”',19);
 txt(s,'小明把书放在桌上，因为它很稳。',80,170,760,62,34,C.ink,true);const words=[['它',720,C.orange],['桌',468,C.blue],['书',230,C.cyan]];words.forEach(([w,x,c])=>{dot(s,x,285,12,c);txt(s,w,x-35,315,70,42,25,c,true,'center');});
 line(s,720,285,-252,0,C.blue,8);line(s,720,285,-490,0,C.cyan,3);txt(s,'注意力权重较高',430,235,210,34,20,C.blue,true,'center');txt(s,'权重较低',235,245,150,34,18,C.cyan,false,'center');
 box(s,865,150,335,340,C.white,18,C.grid);txt(s,'注意力机制',900,180,265,44,29,C.orange,true,'center');txt(s,'为不同词分配不同权重',900,245,265,70,23,C.ink,false,'center');txt(s,'聚焦当前任务最相关的信息',900,335,265,70,23,C.ink,false,'center');
 txt(s,'Transformer = 注意力模块 + 前馈网络 + 残差连接等结构',150,570,980,58,29,C.ink,true,'center');notes(s,'注意力让每个词根据当前上下文，从其他词中选择信息。这里用代词指代作直觉示例。','Vaswani et al. (2017), Attention Is All You Need.');
}
//20
{
 const s=base();txt(s,'带走这 5 句话',56,50,500,60,42,C.ink,true);const items=['拟合：用参数找到数据中的规律','损失：把预测错误变成可优化的数字','泛化：新数据表现比训练表现更重要','神经网络：许多可学习的神经元分层组合','现代 AI：用注意力动态选择最相关的信息'];items.forEach((v,i)=>{txt(s,`${i+1}`,72,160+i*88,58,50,30,[C.blue,C.orange,C.green,C.red,C.cyan][i],true,'center');txt(s,v,155,160+i*88,940,50,27,C.ink,i===2);});box(s,860,598,350,54,C.ink,16,'none');txt(s,'下一步：亲手训练一个小模型',880,605,310,40,20,C.white,true,'center');notes(s,'收束：请听众用这五句话复述整套逻辑。','No external assets. Educational synthesis by OpenAI.');
}

await fs.mkdir(RENDER,{recursive:true});
for(let i=0;i<p.slides.items.length;i++){
 const b=await p.export({slide:p.slides.items[i],format:'png',scale:1});
 await fs.writeFile(`${RENDER}/slide-${String(i+1).padStart(2,'0')}.png`,new Uint8Array(await b.arrayBuffer()));
 const l=await p.slides.items[i].export({format:'layout'});await fs.writeFile(`${RENDER}/slide-${String(i+1).padStart(2,'0')}.layout.json`,await l.text());
}
const pptx=await PresentationFile.exportPptx(p);await pptx.save(OUT);
console.log(OUT);
