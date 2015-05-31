from django.shortcuts import render
from vote.models import scoreDep

def home(request):
	score=scoreDep.objects.order_by('NumDep').order_by('-ScoreDep')[:100:1]
	return render(request,'carto/carto.html',{'score':score})

