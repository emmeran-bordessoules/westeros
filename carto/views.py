from django.shortcuts import render
from vote.models import scoreDep,Vote

def home(request):
	score=scoreDep.objects.order_by('NumDep').order_by('-ScoreDep')[:8:1]
	return render(request,'carto/carto.html',{'score':score})


	
	
	